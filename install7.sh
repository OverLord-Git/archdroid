#!/usr/bin/env bash
# ARCHDROID ULTIMATE INSTALLER v10.0 (All-in-One)
set -euo pipefail
trap 'cleanup && exit 1' ERR

# Configuración Unificada
declare -A CFG=(
    [USER]="archuser"        [PASS]="$(openssl rand -base64 12)"
    [HOST]="archdroid"       [DISK]="/dev/nvme0n1"
    [TZ]="America/New_York"  [KERNEL]="linux-zen"
    [FS]="btrfs"             [DE]="gnome"
    [GPU]="auto"             [MODE]="desktop"
    [AI_MODEL]="deepseek-7b-Q8_0"
)

# Servidores de Respaldo
MIRRORS=(
    "https://mirror.cachyos.org/repo/x86_64/cachyos"
    "https://mirror.rackspace.com/archlinux/\$repo/os/\$arch"
    "https://archlinux.mirror.liquidtelecom.com/\$repo/os/\$arch"
)

# Funciones Principales
init() {
    check_uefi
    setup_clock
    loadkeys us
    configure_mirrors
    connect_network
}

check_uefi() {
    [[ -d /sys/firmware/efi ]] || {
        echo "❌ Sistema no UEFI"; exit 1
    }
}

connect_network() {
    while ! ping -c1 archlinux.org; do
        echo "🔄 Intentando conectar a red..."
        for iface in $(ls /sys/class/net | grep -v lo); do
            dhcpcd "$iface" && return 0
        done
        sleep 5
    done
}

configure_mirrors() {
    reflector --latest 20 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
    for mirror in "${MIRRORS[@]}"; do
        echo "Server = $mirror" >> /etc/pacman.d/mirrorlist
    done
}

partition_disk() {
    parted -s "${CFG[DISK]}" mklabel gpt
    parted -s "${CFG[DISK]}" mkpart ESP fat32 1MiB 513MiB set 1 esp on
    parted -s "${CFG[DISK]}" mkpart primary 513MiB 100%
    
    mkfs.fat -F32 "${CFG[DISK]}p1"
    cryptsetup luksFormat --type luks2 "${CFG[DISK]}p2" <<< "${CFG[PASS]}"
    cryptsetup open "${CFG[DISK]}p2" cryptroot <<< "${CFG[PASS]}"
    
    mkfs.btrfs -L ROOT /dev/mapper/cryptroot
    mount /dev/mapper/cryptroot /mnt
    mkdir -p /mnt/boot && mount "${CFG[DISK]}p1" /mnt/boot
}

install_base() {
    local packages=(
        base base-devel linux-zen linux-zen-headers grub efibootmgr networkmanager 
        git zsh reflector flatpak appimagelauncher nvidia-dkms vulkan-icd-loader 
        lib32-nvidia-utils python-pip python-venv python-numpy
    )
    
    pacstrap /mnt "${packages[@]}"
    genfstab -U /mnt >> /mnt/etc/fstab
}

setup_gpu() {
    case "$(lspci | grep -i 'vga\|3d')" in
        *NVIDIA*)
            arch-chroot /mnt bash -c "pacman -S --noconfirm nvidia-utils lib32-nvidia-utils && nvidia-modprobe"
            ;;
        *AMD*)
            arch-chroot /mnt bash -c "pacman -S --noconfirm vulkan-radeon lib32-vulkan-radeon amdvlk"
            ;;
        *Intel*)
            arch-chroot /mnt bash -c "pacman -S --noconfirm vulkan-intel lib32-vulkan-intel intel-media-driver"
            ;;
    esac
}

configure_system() {
    arch-chroot /mnt /bin/bash <<EOF
    ln -sf "/usr/share/zoneinfo/${CFG[TZ]}" /etc/localtime
    hwclock --systohc
    echo "LANG=en_US.UTF-8" > /etc/locale.conf
    echo "${CFG[HOST]}" > /etc/hostname
    
    useradd -m -G wheel,network,video,audio,storage -s /bin/zsh "${CFG[USER]}"
    echo "${CFG[USER]}:${CFG[PASS]}" | chpasswd
    echo "root:${CFG[PASS]}" | chpasswd
    echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/10-archdroid
    
    systemctl enable NetworkManager fstrim.timer systemd-oomd
EOF
}

deploy_ai() {
    local ai_dir="/opt/deepseek"
    arch-chroot /mnt /bin/bash <<EOF
    python -m venv "${ai_dir}/venv"
    source "${ai_dir}/venv/bin/activate"
    pip install llama-cpp-python fastapi uvicorn sse-starlette
    
    wget -P "${ai_dir}/models" \
      https://huggingface.co/TheBloke/deepseek-7B-GGUF/resolve/main/deepseek-7b.Q8_0.gguf
    
    tee /etc/systemd/system/deepseek.service <<'END'
[Unit]
Description=DeepSeek AI Service
After=network.target

[Service]
User=${CFG[USER]}
WorkingDirectory=${ai_dir}
ExecStart=${ai_dir}/venv/bin/uvicorn main:app --host 0.0.0.0 --port 8000
Restart=always

[Install]
WantedBy=multi-user.target
END

    systemctl enable deepseek.service
EOF
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

cleanup() {
    umount -R /mnt 2>/dev/null || true
    cryptsetup close cryptroot 2>/dev/null || true
}

# Flujo de Instalación Unificado
main() {
    init
    partition_disk
    install_base
    setup_gpu
    configure_system
    deploy_ai
    setup_desktop
    
    echo "✅ Instalación completada!"
    echo "   Usuario: ${CFG[USER]}"
    echo "   Contraseña: ${CFG[PASS]}"
    echo "   AI API: http://localhost:8000/docs"
    echo "   Reinicia con: reboot"
}

main
