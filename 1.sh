#!/bin/bash

# AndroNix-OS Creator - Versión con Gestión de Usuarios
# Licencia: GPLv3

# Función para validar entrada de usuario
validate_input() {
    while true; do
        read -p "$1" input
        if [[ "$input" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
            echo "$input"
            break
        else
            echo "Error: Nombre de usuario inválido. Solo letras minúsculas, números, '-', y '_'. Empiece con letra."
        fi
    done
}

# Configuración de usuario interactiva
setup_credentials() {
    echo -e "\n>>> Configuración de Usuario <<<"
    username=$(validate_input "Ingrese nombre de usuario: ")
    
    while true; do
        read -sp "Contraseña para $username: " user_password
        echo
        read -sp "Confirme la contraseña: " user_password_confirm
        echo
        [ "$user_password" == "$user_password_confirm" ] && break
        echo "Error: Las contraseñas no coinciden. Intente nuevamente."
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

check_uefi() {
    [ ! -d /sys/firmware/efi ] && echo "ERROR: Se requiere UEFI!" && exit 1
    [ "$(id -u)" -ne 0 ] && echo "ERROR: Se requiere ejecutar como root!" && exit 1
}

detect_hardware() {
    DISK=$(lsblk -dno NAME -e 7,11 | grep -E 'nvme|sda|mmc' | head -1)
    [ -z "$DISK" ] && echo "ERROR: No se encontró disco válido!" && exit 1
    SSD=$(lsblk -d -o rota /dev/$DISK | grep -w 0 && SSD_OPTIONS="discard,noatime")
}

partition_setup() {
    echo "Configurando particiones en /dev/$DISK..."
    parted --script /dev/$DISK mklabel gpt
    parted --script /dev/$DISK mkpart "EFI" fat32 1MiB 513MiB
    parted --script /dev/$DISK set 1 esp on
    parted --script /dev/$DISK mkpart "root" ext4 513MiB 100%
    
    mkfs.fat -F32 /dev/${DISK}p1
    mkfs.ext4 /dev/${DISK}p2 -L AndroNix-OS
    mount /dev/${DISK}p2 /mnt
    mkdir -p /mnt/boot/efi
    mount /dev/${DISK}p1 /mnt/boot/efi
}

install_base() {
    echo "Instalando sistema base..."
    pacstrap /mnt base linux-zen linux-zen-headers linux-firmware \
              base-devel git reflector networkmanager \
              python python-pip xorg-server gnome bash zram-generator \
              sudo vim grub efibootmgr dosfstools os-prober mtools
}

configure_system() {
    genfstab -U /mnt >> /mnt/etc/fstab
    [ -n "$SSD_OPTIONS" ] && sed -i "s|relatime|$SSD_OPTIONS|g" /mnt/etc/fstab

    # Guardar credenciales temporalmente
    echo "$username:$user_password:$root_password" > /mnt/tmp/install_creds
    chmod 600 /mnt/tmp/install_creds

    arch-chroot /mnt bash -c '
        # Cargar credenciales
        IFS=":" read -r username user_password root_password < /tmp/install_creds
        rm -f /tmp/install_creds

        # Configuración básica
        echo "AndroNix-OS" > /etc/hostname
        ln -sf /usr/share/zoneinfo/America/Mexico_City /etc/localtime
        hwclock --systohc
        
        # Configurar locale
        echo "es_MX.UTF-8 UTF-8" > /etc/locale.gen
        locale-gen
        echo "LANG=es_MX.UTF-8" > /etc/locale.conf
        
        # Configurar red
        echo "127.0.0.1   localhost" > /etc/hosts
        echo "::1         localhost" >> /etc/hosts
        echo "127.0.1.1   AndroNix-OS.localdomain AndroNix-OS" >> /etc/hosts
        
        # Instalar GRUB
        grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
        grub-mkconfig -o /boot/grub/grub.cfg
        
        # CORRECCIÓN: Habilitar multilib con sintaxis adecuada
        sed -i "/\[multilib\]/,/Include/!s/^#//" /etc/pacman.conf
        pacman -Sy
        
        # Crear usuario y contraseñas
        useradd -m -G wheel -s /bin/bash "$username"
        echo "$username:$user_password" | chpasswd
        
        # Configurar contraseña de root si se proporcionó
        [ -n "$root_password" ] && echo "root:$root_password" | chpasswd || passwd -l root
        
        # Configurar sudoers
        echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/wheel
        echo "Defaults timestamp_timeout=30" >> /etc/sudoers.d/wheel
        chmod 440 /etc/sudoers.d/wheel


        # Instalar yay
        su - "$username" -c "
            git clone https://aur.archlinux.org/yay.git
            cd yay
            makepkg -si --noconfirm
            cd ..
            rm -rf yay
        "

        # Paquetes adicionales
        pacman -S --noconfirm flatpak wine-staging steam lib32-mesa \
                  noto-fonts-cjk noto-fonts-emoji

        # Instalar Waydroid
        su - "$username" -c "yay -S --noconfirm waydroid"
        su - "$username" -c "waydroid init"
        
        # Servicios
        systemctl enable NetworkManager
        systemctl enable gdm
        systemctl enable waydroid
    '
}

post_install() {
    echo "Configurando optimizaciones..."
    mkdir -p /mnt/etc/systemd/
    echo "[zram0]" > /mnt/etc/systemd/zram-generator.conf
    echo "zram-size = ram / 2" >> /mnt/etc/systemd/zram-generator.conf

    mkdir -p /mnt/etc/sysctl.d/
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
    echo -e "\nInstalación completada exitosamente!"
    echo "========================================"
    echo "Usuario: $username"
    echo "Contraseña de usuario: [la que ingresó]"
    [ -n "$root_password" ] && echo "Contraseña de root: [la que ingresó]" || echo "Cuenta root: deshabilitada"
    echo "Reinicia el sistema y retira el medio de instalación."
}

main
