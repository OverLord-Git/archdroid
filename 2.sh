#!/bin/bash

# AndroNix-OS - Instalador Definitivo
# Licencia: GPLv3

# Función para limpiar pantalla
clean_screen() {
    clear
    echo "================================================"
    echo "        Instalador AndroNix-OS - Versión 2.1     "
    echo "================================================"
}

# Validación de nombre de usuario
validate_username() {
    while true; do
        read -p "Ingrese nombre de usuario: " username
        if [[ "$username" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] && [[ ! "$username" =~ _-|-_ ]]; then
            return 0
        else
            echo "Error: Nombre inválido. Debe:"
            echo "- Comenzar con letra minúscula"
            echo "- Contener solo letras, números, _ y -"
            echo "- Máximo 32 caracteres"
        fi
    done
}

# Configuración de credenciales
setup_credentials() {
    clean_screen
    echo -e "\n>>> Configuración de Usuario <<<"
    validate_username
    
    while true; do
        read -sp "Contraseña para $username: " user_password
        echo
        read -sp "Confirme la contraseña: " user_password_confirm
        echo
        [ "$user_password" == "$user_password_confirm" ] && break
        echo "Error: Las contraseñas no coinciden."
    done

    echo -e "\n>>> Contraseña de root (opcional) <<<"
    read -sp "Contraseña para root (dejar vacío para deshabilitar): " root_password
    echo
    [ -n "$root_password" ] && {
        read -sp "Confirme la contraseña de root: " root_password_confirm
        echo
        [ "$root_password" != "$root_password_confirm" ] && {
            echo "Error: Contraseñas de root no coinciden. Se continuará sin contraseña de root."
            root_password=""
        }
    }
}

# Verificación UEFI
check_uefi() {
    [ ! -d /sys/firmware/efi ] && echo "ERROR: Se requiere modo UEFI!" && exit 1
    [ "$(id -u)" -ne 0 ] && echo "ERROR: Ejecutar como root!" && exit 1
}

# Detección de hardware
detect_hardware() {
    DISK=$(lsblk -dno NAME -e 7,11 | grep -E 'nvme|sda|mmc' | head -1)
    [ -z "$DISK" ] && echo "ERROR: No se detectó disco!" && exit 1
    
    # Detectar tipo de almacenamiento
    SSD=$(lsblk -d -o rota /dev/$DISK | grep -w 0 && SSD_OPTIONS="discard,noatime")
    
    # Detectar GPU
    GPU=$(lspci | grep -E "VGA|3D" | awk -F ': ' '{print $2}')
    [[ "$GPU" == *"NVIDIA"* ]] && GPU_DRIVER="nvidia-dkms nvidia-utils lib32-nvidia-utils"
    [[ "$GPU" == *"AMD"* ]] && GPU_DRIVER="mesa lib32-mesa vulkan-radeon"
    [[ "$GPU" == *"Intel"* ]] && GPU_DRIVER="mesa lib32-mesa vulkan-intel"
    
    # Detectar microcódigo
    CPU=$(grep -m 1 vendor_id /proc/cpuinfo | awk '{print $3}')
    [ "$CPU" == "GenuineIntel" ] && MICROCODE="intel-ucode"
    [ "$CPU" == "AuthenticAMD" ] && MICROCODE="amd-ucode"
}

# Particionado
partition_setup() {
    clean_screen
    echo "Configurando particiones en /dev/$DISK..."
    
    # Crear tabla de particiones GPT
    parted --script /dev/$DISK mklabel gpt
    
    # Partición EFI (512MB)
    parted --script /dev/$DISK mkpart "EFI" fat32 1MiB 513MiB
    parted --script /dev/$DISK set 1 esp on
    
    # Partición raíz (resto del espacio)
    parted --script /dev/$DISK mkpart "root" ext4 513MiB 100%
    
    # Formatear particiones
    mkfs.fat -F32 /dev/${DISK}p1
    mkfs.ext4 /dev/${DISK}p2 -L AndroNix-OS
    
    # Montar particiones
    mount /dev/${DISK}p2 /mnt
    mkdir -p /mnt/boot/efi
    mount /dev/${DISK}p1 /mnt/boot/efi
}

# Instalación base
install_base() {
    clean_screen
    echo "Instalando sistema base..."
    
    pacstrap /mnt base linux-zen linux-zen-headers linux-firmware \
              $MICROCODE $GPU_DRIVER base-devel git reflector \
              networkmanager gnome gnome-extra gdm xorg-server \
              noto-fonts noto-fonts-cjk noto-fonts-emoji \
              pipewire pipewire-pulse pipewire-alsa sof-firmware \
              vulkan-icd-loader lib32-vulkan-icd-loader \
              zram-generator bash-completion sudo
}

# Configuración del sistema
configure_system() {
    genfstab -U /mnt >> /mnt/etc/fstab
    
    # Optimizaciones SSD
    [ -n "$SSD_OPTIONS" ] && sed -i "s|relatime|$SSD_OPTIONS|g" /mnt/etc/fstab

    # Escribir credenciales
    echo "$username:$user_password:$root_password" > /mnt/tmp/install_creds
    chmod 600 /mnt/tmp/install_creds

    arch-chroot /mnt bash -c '
        # Cargar credenciales
        IFS=":" read -r username user_password root_password < /tmp/install_creds
        rm -f /tmp/install_creds
        
        [ -z "$username" ] && { echo "Error: Nombre de usuario vacío"; exit 1; }

        # Configuración básica
        echo "AndroNix-OS" > /etc/hostname
        ln -sf /usr/share/zoneinfo/America/Mexico_City /etc/localtime
        hwclock --systohc
        
        # Locale
        echo "es_MX.UTF-8 UTF-8" > /etc/locale.gen
        locale-gen
        echo "LANG=es_MX.UTF-8" > /etc/locale.conf
        
        # Red
        echo "127.0.0.1   localhost" > /etc/hosts
        echo "::1         localhost" >> /etc/hosts
        echo "127.0.1.1   AndroNix-OS.localdomain AndroNix-OS" >> /etc/hosts
        
        # Configurar GRUB (corregir pantalla gris)
        grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
        sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=".*"/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet splash"/' /etc/default/grub
        grub-mkconfig -o /boot/grub/grub.cfg
        
        # Habilitar multilib
        sed -i "/\[multilib\]/,/Include/ s/^#//" /etc/pacman.conf
        pacman -Sy
        
        # Crear usuario
        useradd -m -G wheel,audio,video,storage -s /bin/bash "$username"
        echo "$username:$user_password" | chpasswd
        
        # Configurar sudo
        echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel
        echo "Defaults:%wheel timestamp_timeout=15" >> /etc/sudoers.d/wheel
        chmod 440 /etc/sudoers.d/wheel

        # Configurar root
        if [ -n "$root_password" ]; then
            echo "root:$root_password" | chpasswd
        else
            passwd -l root
        fi

        # Instalar yay
        su - "$username" -c '
            'git clone https://aur.archlinux.org/yay.git &&
            cd yay &&
            makepkg -si --noconfirm &&
            cd .. &&
            rm -rf yay'
        '

        # Instalar paquetes adicionales
        pacman -S --noconfirm flatpak firefox steam wine-staging
        
        # Configurar Waydroid
        su - "$username" -c "yay -S --noconfirm waydroid"
        su - "$username" -c "waydroid init"
        
        # Configurar servicios
        systemctl enable gdm
        systemctl enable NetworkManager
        systemctl enable waydroid
        
        # Corregir pantalla gris en GDM
        ln -s /dev/null /etc/udev/rules.d/61-gdm.rules
    '
}

# Post-instalación
post_install() {
    # Optimizaciones de memoria
    echo "[zram0]" > /mnt/etc/systemd/zram-generator.conf
    echo "zram-size = ram / 2" >> /mnt/etc/systemd/zram-generator.conf
    
    # Optimizaciones del kernel
    echo "vm.swappiness=10" > /mnt/etc/sysctl.d/99-optimization.conf
    echo "vm.vfs_cache_pressure=50" >> /mnt/etc/sysctl.d/99-optimization.conf
}

main() {
    check_uefi
    setup_credentials
    detect_hardware
    partition_setup
    install_base
    configure_system
    post_install
    
    umount -R /mnt
    clean_screen
    echo "Instalación completada correctamente!"
    echo "========================================"
    echo "Usuario: $username"
    echo "Contraseña: [la ingresada durante la instalación]"
    echo -e "\nReinicia el sistema y:"
    echo "1. Selecciona 'GNOME' en el gestor de inicio"
    echo "2. Para Waydroid: ejecuta 'waydroid session start'"
    echo "3. Para problemas gráficos: instala drivers específicos"
}

main
