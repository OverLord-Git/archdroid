#!/usr/bin/env bash
# ARCHDROID ULTIMATE INSTALLER v14.0 (Stable Release)
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
readonly REQUIRED_PACKAGES="git lsb-release sbctl iwd"
readonly COLOR_HEADER="\e[1;36m"
readonly COLOR_SUCCESS="\e[1;32m"
readonly COLOR_ERROR="\e[1;31m"
readonly COLOR_RESET="\e[0m"

# ================== FUNCIONES VISUALES ==================
show_header() {
    clear
    echo -e "${COLOR_HEADER}"
    echo " █████╗ ██████╗  ██████╗██╗  ██╗██████╗ ██████╗ ██████╗ ██╗██████╗ "
    echo "██╔══██╗██╔══██╗██╔════╝██║  ██║██╔══██╗██╔══██╗██╔══██╗██║██╔══██╗"
    echo "███████║██████╔╝██║     ███████║██║  ██║██████╔╝██║  ██║██║██║  ██║"
    echo "██╔══██║██╔══██╗██║     ██╔══██║██║  ██║██╔══██╗██║  ██║██║██║  ██║"
    echo "██║  ██║██║  ██║╚██████╗██║  ██║██████╔╝██║  ██║██████╔╝██║██████╔╝"
    echo "╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝╚═════╝ ╚═╝  ╚═╝╚═════╝ ╚═╝╚═════╝ "
    echo -e "${COLOR_RESET}"
    echo -e "${COLOR_HEADER}Instalador Automático de Arch Linux - Versión 14.0${COLOR_RESET}"
    echo "=============================================================="
}

step_header() {
    echo -e "\n${COLOR_HEADER}[$1] $2${COLOR_RESET}"
    echo "--------------------------------------------------------------"
}

# ================== FUNCIONES PRINCIPALES ==================
setup_clock() {
    timedatectl set-ntp true
    hwclock --systohc --utc
}

init_system() {
    show_header
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
        echo -e "${COLOR_ERROR}[ERROR] Se requiere sistema UEFI${COLOR_RESET}"
        exit 1
    }
}

detect_virtualization() {
    local virt=$(systemd-detect-virt)
    if [[ $virt != "none" ]]; then
        CFG[VIRTUALIZATION]=$virt
        case $virt in
            "vmware")    CFG[KERNEL]="linux" ;;
            "oracle")    CFG[KERNEL]="linux-lts" ;;
            "qemu")      CFG[KERNEL]="linux" ;;
        esac
        step_header "VIRTUALIZACIÓN" "Detectado: ${COLOR_HEADER}${virt}${COLOR_RESET}"
    fi
}

install_required_packages() {
    step_header "PAQUETES" "Instalando dependencias esenciales"
    pacman -Sy --noconfirm --needed $REQUIRED_PACKAGES
}

configure_pacman() {
    sed -i 's/^#Color/Color/' /etc/pacman.conf
    [[ ${CFG[USE_MULTILIB]} -eq 1 ]] && sed -i '/\[multilib\]/,/Include/s/^#//' /etc/pacman.conf
}

# ================== CONFIGURACIÓN INTERACTIVA ==================
setup_interactive() {
    step_header "CONFIGURACIÓN" "Iniciando setup interactivo"
    select_disk
    CFG[USER]=$(read_input "Nombre de usuario" "archuser")
    CFG[HOST]=$(read_input "Nombre del equipo" "archdroid")
    set_password
    CFG[USE_CACHYOS]=$(confirm "¿Habilitar repositorios CachyOS?")
    CFG[USE_SECUREBOOT]=$(confirm "¿Configurar Secure Boot?")
    CFG[USE_FULLDISK_ENCRYPT]=$(confirm "¿Cifrado completo de disco?")
    select_timezone
    select_network
    select_de
    detect_gpu
}

select_disk() {
    echo -e "\nDiscos disponibles:"
    lsblk -dno NAME,SIZE,MODEL -e 7,11
    while true; do
        read -p "Seleccione disco (ej: /dev/nvme0n1): " disk
        [[ -b $disk ]] && {
            CFG[DISK]=$disk
            break
        }
        echo -e "${COLOR_ERROR}¡Disco no válido!${COLOR_RESET}"
    done
}

set_password() {
    local pass
    while true; do
        read -sp "Contraseña para root/usuario: " pass
        echo
        [[ -n $pass ]] && break
        echo -e "${COLOR_ERROR}La contraseña no puede estar vacía${COLOR_RESET}"
    done
    CFG[PASS]=$pass
}

select_timezone() {
    echo -e "\nRegiones disponibles:"
    timedatectl list-timezones | cut -d'/' -f1 | uniq
    CFG[TZ_REGION]=$(read_input "Región horaria" "America")
    
    echo -e "\nCiudades disponibles:"
    timedatectl list-timezones | grep "^${CFG[TZ_REGION]}/" | cut -d'/' -f2
    CFG[TZ_CITY]=$(read_input "Ciudad" "New_York")
}

select_network() {
    local net_choice=$(read_input "Tipo de red [1]Ethernet [2]WiFi" "1")
    [[ $net_choice == "2" ]] && setup_wifi
}

setup_wifi() {
    iwctl device list
    local device=$(read_input "Dispositivo WiFi")
    iwctl station $device scan
    
    echo -e "\nRedes disponibles:"
    iwctl station $device get-networks
    local ssid=$(read_input "SSID")
    local pass=$(read_password "Contraseña WiFi")
    
    iwctl --passphrase "$pass" station $device connect "$ssid"
    sleep 5
    verify_internet
}

select_de() {
    local de_choice=$(read_input "Entorno de escritorio [1]GNOME [2]KDE [3]XFCE" "1")
    case $de_choice in
        1) CFG[DE]="gnome" ;;
        2) CFG[DE]="kde" ;;
        3) CFG[DE]="xfce" ;;
    esac
}

detect_gpu() {
    local gpu_info=$(lspci | grep -i 'vga\|3d')
    case $gpu_info in
        *NVIDIA*) CFG[GPU_TYPE]="nvidia" ;;
        *AMD*)    CFG[GPU_TYPE]="amd" ;;
        *Intel*)  CFG[GPU_TYPE]="intel" ;;
        *)        CFG[GPU_TYPE]="generic" ;;
    esac
    step_header "HARDWARE" "GPU detectada: ${COLOR_HEADER}${CFG[GPU_TYPE]}${COLOR_RESET}"
}

# ================== INSTALACIÓN DEL SISTEMA ==================
secure_partition() {
    step_header "PARTICIONADO" "Configurando ${COLOR_HEADER}${CFG[DISK]}${COLOR_RESET}"
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
    step_header "INSTALACIÓN" "Instalando sistema base"
    local base_packages=(
        base base-devel ${CFG[KERNEL]} ${CFG[KERNEL]}-headers grub efibootmgr 
        networkmanager git zsh reflector flatpak appimagelauncher
        intel-ucode amd-ucode mkinitcpio linux-firmware
    )
    
    [[ "${CFG[VIRTUALIZATION]}" != "none" ]] && base_packages+=(
        virtualbox-guest-utils open-vm-tools qemu-guest-agent
    )
    
    pacstrap /mnt "${base_packages[@]}"
    genfstab -U /mnt >> /mnt/etc/fstab
}

# ================== POST-INSTALACIÓN ==================
configure_system() {
    step_header "CONFIGURACIÓN" "Aplicando ajustes finales"
    arch-chroot /mnt /bin/bash <<EOF
    ln -sf "/usr/share/zoneinfo/${CFG[TZ_REGION]}/${CFG[TZ_CITY]}" /etc/localtime
    hwclock --systohc
    echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
    locale-gen
    echo "LANG=en_US.UTF-8" > /etc/locale.conf
    echo "${CFG[HOST]}" > /etc/hostname
    
    useradd -m -G wheel,network,video,audio,storage -s /bin/zsh "${CFG[USER]}"
    echo "${CFG[USER]}:${CFG[PASS]}" | chpasswd
    echo "root:${CFG[PASS]}" | chpasswd
    echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/10-archdroid
    chmod 440 /etc/sudoers.d/10-archdroid
    
    # Configuración de GRUB
    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=ARCHDROID
    sed -i "s/GRUB_DEFAULT=.*/GRUB_DEFAULT=saved/" /etc/default/grub
    sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT=\"loglevel=3 quiet\"/" /etc/default/grub
    
    # Enlaces de kernel
    ln -sf vmlinuz-${CFG[KERNEL]} /boot/vmlinuz-linux 2>/dev/null || true
    ln -sf initramfs-${CFG[KERNEL]}.img /boot/initramfs-linux.img 2>/dev/null || true
    
    # Initramfs
    sed -i 's/HOOKS=.*/HOOKS=(base systemd autodetect modconf block filesystems keyboard fsck)/' /etc/mkinitcpio.conf
    mkinitcpio -P
    
    # Secure Boot
    [[ ${CFG[USE_SECUREBOOT]} -eq 1 ]] && {
        sbctl create-keys
        sbctl enroll-keys -m
        sbctl sign -s /boot/EFI/BOOT/BOOTX64.EFI
        sbctl sign -s /boot/vmlinuz-${CFG[KERNEL]}
    }
    
    grub-mkconfig -o /boot/grub/grub.cfg
    systemctl enable NetworkManager fstrim.timer systemd-oomd
EOF
}

setup_gpu() {
    step_header "GPU" "Instalando controladores: ${COLOR_HEADER}${CFG[GPU_TYPE]}${COLOR_RESET}"
    arch-chroot /mnt /bin/bash <<EOF
    case "${CFG[GPU_TYPE]}" in
        "nvidia")
            pacman -S --noconfirm nvidia-dkms nvidia-utils lib32-nvidia-utils nvidia-settings
            echo "options nvidia-drm modeset=1" > /etc/modprobe.d/nvidia.conf
            mkinitcpio -P
            ;;
        "amd")
            pacman -S --noconfirm mesa vulkan-radeon lib32-vulkan-radeon amdvlk
            ;;
        "intel")
            pacman -S --noconfirm mesa vulkan-intel lib32-vulkan-intel intel-media-driver
            ;;
        *)
            pacman -S --noconfirm mesa vulkan-icd-loader lib32-vulkan-icd-loader
            ;;
    esac
EOF
}

setup_desktop() {
    step_header "ESCRITORIO" "Instalando: ${COLOR_HEADER}${CFG[DE]}${COLOR_RESET}"
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

# ================== FUNCIONES AUXILIARES ==================
cleanup() {
    umount -R /mnt 2>/dev/null || true
    [[ ${CFG[USE_FULLDISK_ENCRYPT]} -eq 1 ]] && cryptsetup close cryptroot || true
}

read_input() {
    read -p "$1 [${2}]: " input
    echo "${input:-$2}"
}

read_password() {
    local pass
    read -sp "$1: " pass
    echo
    echo "$pass"
}

confirm() {
    read -p "$1 [y/N]: " -n 1 -r
    [[ $REPLY =~ ^[Yy]$ ]] && echo 1 || echo 0
}

verify_internet() {
    until ping -c1 archlinux.org; do
        echo -e "${COLOR_ERROR}Esperando conexión a internet...${COLOR_RESET}"
        sleep 5
    done
}

setup_mirrors() {
    reflector --latest 20 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
    [[ ${CFG[USE_CACHYOS]} -eq 1 ]] && echo -e "\nServer = https://mirror.cachyos.org/repo/x86_64/cachyos\n" >> /etc/pacman.d/mirrorlist
}

# ================== EJECUCIÓN PRINCIPAL ==================
main() {
    init_system
    setup_interactive
    secure_partition
    install_system
    configure_system
    setup_gpu
    setup_desktop
    
    echo -e "\n${COLOR_SUCCESS}¡Instalación completada con éxito!${COLOR_RESET}"
    echo -e "Usuario: ${COLOR_HEADER}${CFG[USER]}${COLOR_RESET}"
    echo -e "Hostname: ${COLOR_HEADER}${CFG[HOST]}${COLOR_RESET}"
    echo -e "Kernel: ${COLOR_HEADER}${CFG[KERNEL]}${COLOR_RESET}"
    echo -e "Reinicia con: ${COLOR_HEADER}systemctl reboot${COLOR_RESET}\n"
}

main