#!/usr/bin/env bash
# ARCHDROID PRO ULTIMATE INSTALLER v11.0 (Secure/Interactive)
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
)

# Constantes
readonly MIRRORLIST_URL="https://archlinux.org/mirrorlist/all/"
readonly AI_MODEL_CHECKSUM="a1b2c3d4e5f6..."
readonly REQUIRED_PACKAGES="git lsb-release sbctl iwd"

# Inicialización del sistema
init_system() {
    check_uefi
    setup_clock
    loadkeys us
    verify_internet
    install_required_packages
    configure_pacman
    setup_mirrors
}

check_uefi() {
    [[ -d /sys/firmware/efi ]] || {
        echo "ERROR: UEFI required for installation"
        exit 1
    }
}

install_required_packages() {
    pacman -Sy --noconfirm --needed $REQUIRED_PACKAGES
}

configure_pacman() {
    sed -i 's/^#Color/Color/' /etc/pacman.conf
    [[ ${CFG[USE_MULTILIB]} -eq 1 ]] && sed -i '/\[multilib\]/,/Include/s/^#//' /etc/pacman.conf
}

# Configuración interactiva
setup_interactive() {
    CFG[DISK]=$(select_disk)
    CFG[USER]=$(read_input "Enter username: " "archuser")
    CFG[HOST]=$(read_input "Enter hostname: " "archdroid")
    
    local pass=$(read_password "Enter password: ")
    CFG[PASS]="${pass:-$(openssl rand -base64 12)}"
    
    CFG[USE_CACHYOS]=$(confirm "Enable CachyOS repositories?")
    CFG[USE_SECUREBOOT]=$(confirm "Configure Secure Boot?")
    CFG[USE_FULLDISK_ENCRYPT]=$(confirm "Enable full disk encryption?")
    
    select_timezone
    select_network
    select_de
}

select_disk() {
    echo "Available disks:"
    lsblk -dno NAME,SIZE,MODEL | grep -v 'loop'
    read -p "Select disk (e.g., /dev/nvme0n1): " disk
    echo "$disk"
}

select_timezone() {
    echo "Regions:"
    timedatectl list-timezones | cut -d'/' -f1 | uniq
    CFG[TZ_REGION]=$(read_input "Enter region: " "America")
    
    echo "Cities:"
    timedatectl list-timezones | grep "^${CFG[TZ_REGION]}/" | cut -d'/' -f2
    CFG[TZ_CITY]=$(read_input "Enter city: " "New_York")
}

select_network() {
    local net_choice=$(read_input "Network type [1]Ethernet [2]WiFi: " "1")
    [[ $net_choice == "2" ]] && setup_wifi
}

setup_wifi() {
    iwctl device list
    local device=$(read_input "Enter WiFi device: ")
    iwctl station $device scan
    
    echo "Available networks:"
    iwctl station $device get-networks
    local ssid=$(read_input "Enter SSID: ")
    local pass=$(read_password "WiFi password: ")
    
    iwctl --passphrase "$pass" station $device connect "$ssid"
    sleep 5
    verify_internet
}

select_de() {
    local de_choice=$(read_input "Desktop Environment [1]GNOME [2]KDE [3]XFCE: " "1")
    case $de_choice in
        1) CFG[DE]="gnome" ;;
        2) CFG[DE]="kde" ;;
        3) CFG[DE]="xfce" ;;
    esac
}

# Configuración de repositorios
setup_mirrors() {
    reflector --latest 20 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
    [[ ${CFG[USE_CACHYOS]} -eq 1 ]] && echo "Server = https://mirror.cachyos.org/repo/x86_64/cachyos" >> /etc/pacman.d/mirrorlist
}

# Particionado seguro
secure_partition() {
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

# Instalación base optimizada
install_system() {
    local base_packages=(
        base base-devel ${CFG[KERNEL]} ${CFG[KERNEL]}-headers grub efibootmgr 
        networkmanager git zsh reflector flatpak appimagelauncher
    )
    
    pacstrap /mnt "${base_packages[@]}"
    genfstab -U /mnt >> /mnt/etc/fstab
}

# Configuración segura del sistema
secure_configure() {
    arch-chroot /mnt /bin/bash <<EOF
    # Zona horaria
    ln -sf "/usr/share/zoneinfo/${CFG[TZ_REGION]}/${CFG[TZ_CITY]}" /etc/localtime
    hwclock --systohc
    
    # Localización
    echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
    locale-gen
    echo "LANG=en_US.UTF-8" > /etc/locale.conf
    
    # Hostname
    echo "${CFG[HOST]}" > /etc/hostname
    
    # Usuario seguro
    useradd -m -G wheel,network,video,audio,storage -s /bin/zsh "${CFG[USER]}"
    echo "${CFG[USER]}:${CFG[PASS]}" | chpasswd
    echo "root:${CFG[PASS]}" | chpasswd
    
    # Sudo seguro
    echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/10-archdroid
    chmod 440 /etc/sudoers.d/10-archdroid
    
    # Secure Boot
    if [[ ${CFG[USE_SECUREBOOT]} -eq 1 ]]; then
        sbctl create-keys
        sbctl enroll-keys
        sbctl sign -s /boot/EFI/BOOT/BOOTX64.EFI
    fi
    
    # Servicios esenciales
    systemctl enable NetworkManager fstrim.timer systemd-oomd
EOF
}

# Controladores GPU optimizados
setup_gpu() {
    arch-chroot /mnt /bin/bash <<EOF
    case "${CFG[GPU_TYPE]}" in
        "nvidia")
            pacman -S --noconfirm nvidia-dkms nvidia-utils lib32-nvidia-utils 
            nvidia-xconfig
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

# Implementación AI segura
deploy_ai_safe() {
    arch-chroot /mnt /bin/bash <<EOF
    local ai_dir="/opt/ai_service"
    mkdir -p "$ai_dir"/{models,venv}
    
    python -m venv "$ai_dir/venv"
    source "$ai_dir/venv/bin/activate"
    
    pip install --require-hashes -r <(echo "
        llama-cpp-python==0.2.23 --hash=sha256:...
        fastapi==0.104.1 --hash=sha256:...
    ")
    
    # Descarga segura con verificación
    wget -P "$ai_dir/models" "https://huggingface.co/model/${CFG[AI_MODEL]}"
    echo "${AI_MODEL_CHECKSUM}  $ai_dir/models/${CFG[AI_MODEL]}" | sha256sum -c
    
    # Configuración del servicio con hardening
    tee /etc/systemd/system/ai_service.service <<'END'
[Unit]
Description=Secure AI Service
After=network.target
ConditionPathExists=|/opt/ai_service

[Service]
User=${CFG[USER]}
Group=${CFG[USER]}
WorkingDirectory=/opt/ai_service
ExecStart=/opt/ai_service/venv/bin/uvicorn main:app --host 127.0.0.1 --port 8000
PrivateTmp=true
NoNewPrivileges=true
ProtectSystem=strict
RestrictSUIDSGID=true

[Install]
WantedBy=multi-user.target
END

    systemctl enable ai_service
EOF
}

# Menú de limpieza
cleanup() {
    umount -R /mnt 2>/dev/null || true
    [[ ${CFG[USE_FULLDISK_ENCRYPT]} -eq 1 ]] && cryptsetup close cryptroot || true
    systemctl stop NetworkManager || true
}

# Flujo principal mejorado
main() {
    init_system
    setup_interactive
    secure_partition
    install_system
    secure_configure
    setup_gpu
    deploy_ai_safe
    setup_desktop
    
    echo "✅ Installation completed successfully!"
    echo "   User: ${CFG[USER]}"
    echo "   Hostname: ${CFG[HOST]}"
    echo "   Password: ${CFG[PASS]}"
    echo "   AI Service: http://localhost:8000/docs"
}

# Funciones auxiliares
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
        echo "Waiting for internet connection..."
        sleep 5
    done
}

setup_desktop() {
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

main
