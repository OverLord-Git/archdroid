#!/usr/bin/env bash
# ARCHDROID INSTALLER v10.1 (Error Handling)
set -euo pipefail
trap 'cleanup && exit 1' ERR

# Configuración Global
declare -A CFG=(
    [USER]="archuser"
    [PASS]="$(openssl rand -base64 12)"
    [HOST]="archdroid"
    [DISK]="/dev/nvme0n1"
    [TZ]="America/New_York"
    [KERNEL]="linux-zen"
    [FS]="btrfs"
    [MODE]="desktop"
)

setup_network() {
    echo "🌐 Configurando red..."
    if ! ping -c 1 archlinux.org &> /dev/null; then
        echo "⚠️ Sin conexión a Internet. Configurando Wi-Fi..."
        iwctl station wlan0 scan
        iwctl station wlan0 connect "${WIFI_SSID}" password "${WIFI_PASS}"
    fi
}

setup_repos() {
    echo "🔄 Configurando repositorios..."
    sudo pacman -S --noconfirm reflector
    sudo reflector --latest 20 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
    
    # Habilitar multilib y community
    sudo sed -i 's/#\[multilib\]/[multilib]/;s/#\[community\]/[community]/' /etc/pacman.conf
    sudo pacman-key --init
    sudo pacman-key --populate archlinux
    sudo pacman -Sy
}

retry_pacman() {
    local max_retries=3
    local retry_count=0
    
    while [[ $retry_count -lt $max_retries ]]; do
        if sudo pacman -Syy; then
            return 0
        else
            retry_count=$((retry_count + 1))
            echo "⚠️ Intento $retry_count fallido. Reintentando..."
            sleep 5
        fi
    done
    
    echo "❌ No se pudo sincronizar las bases de datos después de $max_retries intentos."
    exit 1
}

setup_disk() {
    echo "💾 Particionando disco..."
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

install_system() {
    echo "🚀 Instalando sistema base..."
    pacstrap /mnt base base-devel linux-zen linux-zen-headers grub efibootmgr networkmanager
    genfstab -U /mnt >> /mnt/etc/fstab
}

configure_system() {
    arch-chroot /mnt /bin/bash <<EOF
    ln -sf "/usr/share/zoneinfo/${CFG[TZ]}" /etc/localtime
    hwclock --systohc
    echo "LANG=en_US.UTF-8" > /etc/locale.conf
    echo "KEYMAP=us" > /etc/vconsole.conf
    echo "${CFG[HOST]}" > /etc/hostname
    
    useradd -m -G wheel -s /bin/zsh "${CFG[USER]}"
    echo "${CFG[USER]}:${CFG[PASS]}" | chpasswd
    echo "root:${CFG[PASS]}" | chpasswd
    echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/10-archdroid
    
    systemctl enable NetworkManager fstrim.timer systemd-oomd
EOF
}

cleanup() {
    umount -R /mnt 2>/dev/null || true
    cryptsetup close cryptroot 2>/dev/null || true
}

main() {
    [[ -d /sys/firmware/efi ]] || { echo "❌ Sistema no UEFI"; exit 1; }
    
    setup_network
    setup_repos
    retry_pacman
    setup_disk
    install_system
    configure_system
    
    echo "✅ Instalación completada!"
    echo "   Usuario: ${CFG[USER]}"
    echo "   Password: ${CFG[PASS]}"
    echo "   Reinicia con: reboot"
}

main
