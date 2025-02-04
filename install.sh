#!/usr/bin/env bash
# ARCHDROID HYPER INSTALLER v13.1 (Fixed Dependencies)
set -euo pipefail
trap 'cleanup && exit 1' ERR

# Configuración Dinámica
declare -A CFG=(
    [USER]=""                 [HOST]="archdroid"
    [DISK]=""                 [TZ_REGION]="America"
    [TZ_CITY]="New_York"      [KERNEL]="linux-zen"
    [FS]="btrfs"              [DE]="gnome"
    [GPU_TYPE]="auto"         [MODE]="desktop"
    [USE_CACHYOS]="0"         [USE_MULTILIB]="1"
    [USE_SECUREBOOT]="0"      [USE_FULLDISK_ENCRYPT]="1"
    [AI_MODEL]="deepseek-7b-Q8_0"
    [VIRTUALIZATION]="none"
)

# Constantes
readonly MIRRORLIST_URL="https://archlinux.org/mirrorlist/all/"
readonly AI_MODEL_CHECKSUM="a1b2c3d4e5f6..."
readonly REQUIRED_PACKAGES="git lsb-release sbctl iwd figlet toilet cowsay fortune-mod"

# ================== INICIALIZACIÓN VISUAL ==================
show_banner() {
    clear
    toilet -f future "ARCHDROID" --metal
    cowsay -f $(ls /usr/share/cows | shuf -n1) "$(fortune)"
    echo
}

step_header() {
    echo -e "\n\e[1;36m$(figlet -f slant "$1")\e[0m"
    echo -e "\e[33m$(date '+%T') - $2\e[0m\n"
    echo "=============================================="
}

# ================== FUNCIONES DE INICIALIZACIÓN ==================
setup_clock() {
    timedatectl set-ntp true
    hwclock --systohc --utc
}

init_system() {
    show_banner
    check_uefi
    setup_clock
    loadkeys us
    detect_virtualization
    verify_internet
    install_required_packages
    configure_pacman
    setup_mirrors
}

check_uefi() {
    [[ -d /sys/firmware/efi ]] || {
        echo -e "\e[31mERROR: Se requiere sistema UEFI\e[0m" | toilet -f term
        exit 1
    }
}

detect_virtualization() {
    if [[ $(systemd-detect-virt) != "none" ]]; then
        CFG[VIRTUALIZATION]=$(systemd-detect-virt)
        case "${CFG[VIRTUALIZATION]}" in
            "vmware")    CFG[KERNEL]="linux" ;;
            "oracle")    CFG[KERNEL]="linux-lts" ;;
            "qemu")      CFG[KERNEL]="linux" ;;
        esac
        step_header "VIRTUALIZACION" "Detectado: ${CFG[VIRTUALIZATION]}"
    fi
}

install_required_packages() {
    step_header "PAQUETES" "Instalando dependencias visuales"
    pacman -Sy --noconfirm --needed $REQUIRED_PACKAGES
}

configure_pacman() {
    sed -i 's/^#Color/Color/' /etc/pacman.conf
    [[ ${CFG[USE_MULTILIB]} -eq 1 ]] && sed -i '/\[multilib\]/,/Include/s/^#//' /etc/pacman.conf
}

# ================== CONFIGURACIÓN INTERACTIVA ==================
setup_interactive() {
    step_header "CONFIGURACION" "Iniciando setup interactivo"
    CFG[DISK]=$(select_disk)
    CFG[USER]=$(read_input "Nombre de usuario: " "archuser")
    CFG[HOST]=$(read_input "Nombre del equipo: " "archdroid")
    
    local pass=$(read_password "Contraseña: ")
    CFG[PASS]="${pass:-$(openssl rand -base64 12)}"
    
    CFG[USE_CACHYOS]=$(confirm "¿Habilitar repositorios CachyOS?")
    CFG[USE_SECUREBOOT]=$(confirm "¿Configurar Secure Boot?")
    CFG[USE_FULLDISK_ENCRYPT]=$(confirm "¿Cifrado completo de disco?")
    
    select_timezone
    select_network
    select_de
    select_gpu
}

select_disk() {
    echo "Discos disponibles:"
    lsblk -dno NAME,SIZE,MODEL | grep -v 'loop'
    while true; do
        read -p "Seleccione disco (ej: /dev/nvme0n1): " disk
        [[ -b $disk ]] && break
        echo "¡Disco no válido!"
    done
    echo "$disk"
}

select_timezone() {
    echo "Regiones disponibles:"
    timedatectl list-timezones | cut -d'/' -f1 | uniq
    CFG[TZ_REGION]=$(read_input "Región: " "America")
    
    echo "Ciudades disponibles:"
    timedatectl list-timezones | grep "^${CFG[TZ_REGION]}/" | cut -d'/' -f2
    CFG[TZ_CITY]=$(read_input "Ciudad: " "New_York")
}

select_network() {
    local net_choice=$(read_input "Tipo de red [1]Ethernet [2]WiFi: " "1")
    [[ $net_choice == "2" ]] && setup_wifi
}

setup_wifi() {
    iwctl device list
    local device=$(read_input "Dispositivo WiFi: ")
    iwctl station $device scan
    
    echo "Redes disponibles:"
    iwctl station $device get-networks
    local ssid=$(read_input "SSID: ")
    local pass=$(read_password "Contraseña WiFi: ")
    
    iwctl --passphrase "$pass" station $device connect "$ssid"
    sleep 5
    verify_internet
}

select_de() {
    local de_choice=$(read_input "Entorno de escritorio [1]GNOME [2]KDE [3]XFCE: " "1")
    case $de_choice in
        1) CFG[DE]="gnome" ;;
        2) CFG[DE]="kde" ;;
        3) CFG[DE]="xfce" ;;
    esac
}

select_gpu() {
    local gpu_info=$(lspci | grep -i 'vga\|3d')
    if [[ $gpu_info == *NVIDIA* ]]; then
        CFG[GPU_TYPE]="nvidia"
    elif [[ $gpu_info == *AMD* ]]; then
        CFG[GPU_TYPE]="amd"
    elif [[ $gpu_info == *Intel* ]]; then
        CFG[GPU_TYPE]="intel"
    else
        CFG[GPU_TYPE]="generic"
    fi
}

# ================== CONFIGURACIÓN DEL SISTEMA ==================
secure_partition() {
    step_header "PARTICIONADO" "Configurando disco ${CFG[DISK]}"
    local boot_part="${CFG[DISK]}p1"
    local root_part="${CFG[DISK]}p2"
    
    parted -s "${CFG[DISK]}" mklabel gpt
    parted -s "${CFG[DISK]}" mkpart ESP fat32 1MiB 513MiB set 1 esp on
    parted -s "${CFG[DISK]}" mkpart primary 513MiB 100%
    
    mkfs.fat -F32 "$boot_part"
    
    if [[ ${CFG[USE_FULLDISK_ENCRYPT]} -eq 1 ]]; then
        cryptsetup luksFormat --type luks2 "$root_part"
        cryptsetup open "$root_part" cryptroot
        root_dev="/dev/mapper/cryptroot"
    else
        root_dev="$root_part"
    fi
    
    mkfs.btrfs -L ROOT "$root_dev"
    mount "$root_dev" /mnt
    
    # Subvolúmenes Btrfs
    btrfs subvolume create /mnt/@
    btrfs subvolume create /mnt/@home
    btrfs subvolume create /mnt/@snapshots
    
    umount /mnt
    mount -o subvol=@ "$root_dev" /mnt
    mkdir -p /mnt/{home,.snapshots,boot}
    mount -o subvol=@home "$root_dev" /mnt/home
    mount -o subvol=@snapshots "$root_dev" /mnt/.snapshots
    mount "$boot_part" /mnt/boot
}

install_system() {
    step_header "INSTALACION" "Instalando sistema base"
    local base_packages=(
        base base-devel ${CFG[KERNEL]} ${CFG[KERNEL]}-headers grub efibootmgr 
        networkmanager git zsh reflector flatpak appimagelauncher
        intel-ucode amd-ucode mkinitcpio linux-firmware
    )
    
    [[ "${CFG[VIRTUALIZATION]}" != "none" ]] && base_packages+=(virtualbox-guest-utils open-vm-tools qemu-guest-agent)
    
    pacstrap /mnt "${base_packages[@]}"
    genfstab -U /mnt >> /mnt/etc/fstab
}

secure_configure() {
    step_header "CONFIGURACION" "Aplicando ajustes finales"
    arch-chroot /mnt /bin/bash <<EOF
    # Configuración básica
    ln -sf "/usr/share/zoneinfo/${CFG[TZ_REGION]}/${CFG[TZ_CITY]}" /etc/localtime
    hwclock --systohc
    echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
    locale-gen
    echo "LANG=en_US.UTF-8" > /etc/locale.conf
    echo "${CFG[HOST]}" > /etc/hostname
    
    # Configuración de GRUB mejorada
    echo "GRUB_DEFAULT=saved
GRUB_SAVEDEFAULT=true
GRUB_TIMEOUT=5
GRUB_DISABLE_SUBMENU=y
GRUB_TERMINAL_OUTPUT=console
GRUB_CMDLINE_LINUX_DEFAULT=\"loglevel=3 quiet\"
GRUB_DISABLE_RECOVERY=true" > /etc/default/grub

    if [[ "${CFG[KERNEL]}" != "linux" ]]; then
        sed -i "s/vmlinuz-linux/vmlinuz-${CFG[KERNEL]}/g" /etc/grub.d/10_linux
        sed -i "s/initramfs-linux/initramfs-${CFG[KERNEL]}/g" /etc/grub.d/10_linux
    fi

    # Configuración de virtualización
    case "${CFG[VIRTUALIZATION]}" in
        "vmware") systemctl enable vmtoolsd.service vmware-vmblock-fuse.service ;;
        "oracle") systemctl enable vboxservice.service ;;
        "qemu") systemctl enable qemu-guest-agent ;;
    esac

    # Generación de initramfs
    mkinitcpio -P

    # Instalación de GRUB
    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=ARCHDROID
    grub-mkconfig -o /boot/grub/grub.cfg
    
    # Creación de enlaces seguros
    ln -sf vmlinuz-${CFG[KERNEL]} /boot/vmlinuz-linux
    ln -sf initramfs-${CFG[KERNEL]}.img /boot/initramfs-linux.img
EOF
}

setup_gpu() {
    step_header "GPU" "Instalando controladores gráficos"
    arch-chroot /mnt /bin/bash <<EOF
    case "${CFG[GPU_TYPE]}" in
        "nvidia")
            pacman -S --noconfirm nvidia-dkms nvidia-utils lib32-nvidia-utils nvidia-settings
            echo "options nvidia-drm modeset=1" > /etc/modprobe.d/nvidia.conf
            mkinitcpio -P
            ;;
        "amd")
            pacman -S --noconfirm mesa vulkan-radeon lib32-vulkan-radeon amdvlk radeontop
            ;;
        "intel")
            pacman -S --noconfirm mesa vulkan-intel lib32-vulkan-intel intel-media-driver intel-gpu-tools
            ;;
        *)
            pacman -S --noconfirm mesa vulkan-icd-loader lib32-vulkan-icd-loader
            ;;
    esac
EOF
}

# ================== FUNCIONES AUXILIARES ==================
cleanup() {
    umount -R /mnt 2>/dev/null || true
    [[ ${CFG[USE_FULLDISK_ENCRYPT]} -eq 1 ]] && cryptsetup close cryptroot || true
    systemctl stop NetworkManager || true
}

read_input() {
    read -p "$1" -ei "$2" input
    echo "${input:-$2}"
}

read_password() {
    read -sp "$1" pass
    echo "$pass"
}

confirm() {
    read -p "$1 [y/N]: " -n 1 -r
    echo $([[ $REPLY =~ ^[Yy]$ ]] && echo 1 || echo 0)
}

verify_internet() {
    until ping -c1 archlinux.org; do
        echo "Esperando conexión a internet..."
        sleep 5
    done
}

setup_mirrors() {
    reflector --latest 20 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
    [[ ${CFG[USE_CACHYOS]} -eq 1 ]] && echo -e "\nServer = https://mirror.cachyos.org/repo/x86_64/cachyos\n" >> /etc/pacman.d/mirrorlist
}

setup_desktop() {
    step_header "ESCRITORIO" "Instalando ${CFG[DE]}"
    case "${CFG[DE]}" in
        "gnome") 
            arch-chroot /mnt pacman -S --noconfirm gnome gnome-extra gdm
            arch-chroot /mnt systemctl enable gdm
            ;;
        "kde")
            arch-chroot /mnt pacman -S --noconfirm plasma plasma-nm sddm
            arch-chroot /mnt systemctl enable sddm
            ;;
        "xfce")
            arch-chroot /mnt pacman -S --noconfirm xfce4 xfce4-goodies lightdm
            arch-chroot /mnt systemctl enable lightdm
            ;;
    esac
}

# ================== EJECUCIÓN PRINCIPAL ==================
main() {
    init_system
    setup_interactive
    secure_partition
    install_system
    secure_configure
    setup_gpu
    setup_desktop
    
    step_header "COMPLETADO" "Instalación Finalizada"
    echo "Usuario: ${CFG[USER]}" | toilet -f term
    echo "Hostname: ${CFG[HOST]}" | cowsay -n
    echo "Contraseña: ${CFG[PASS]}" | figlet -f small
    echo "Reinicia con: systemctl reboot" | figlet -f slant
}

main