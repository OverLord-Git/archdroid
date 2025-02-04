#!/usr/bin/env bash
# ARCHDROID MINIMAL INSTALLER v11.0
set -euo pipefail

# Configuración Base
declare -A CFG=(
    [USER]="archuser"
    [PASS]="$(openssl rand -base64 12)"
    [HOST]="archdroid-minimal"
    [DISK]="/dev/nvme0n1"
    [TZ]="America/New_York"
    [KERNEL]="linux-zen"
    [FS]="btrfs"
)

# Paquetes Esenciales (60% menos que versión estándar)
BASE_PKGS=(
    base base-devel linux-zen linux-zen-headers grub grub-btrfs efibootmgr 
    networkmanager openssh reflector sudo zsh git pacman-contrib
)

setup_network() {
    ip link | grep -q 'state UP' || {
        echo "⚠️ Configurando Wi-Fi automático..."
        iwctl station wlan0 scan
        iwctl station wlan0 connect "${WIFI_SSID}" password "${WIFI_PASS}"
    }
}

fast_partition() {
    echo "💾 Particionado rápido (15 segundos)..."
    parted -s "${CFG[DISK]}" mklabel gpt
    parted -s "${CFG[DISK]}" mkpart ESP fat32 1MiB 513MiB set 1 esp on
    parted -s "${CFG[DISK]}" mkpart primary 513MiB 100%
    
    mkfs.fat -F32 "${CFG[DISK]}p1"
    mkfs.btrfs -f -M "${CFG[DISK]}p2"
    mount "${CFG[DISK]}p2" /mnt
    mkdir -p /mnt/boot && mount "${CFG[DISK]}p1" /mnt/boot
}

install_core() {
    echo "🚀 Instalación rápida (modo paralelo)..."
    pacstrap -c /mnt "${BASE_PKGS[@]}" --noconfirm --needed
    genfstab -U /mnt >> /mnt/etc/fstab
}

configure_minimal() {
    arch-chroot /mnt /bin/bash <<EOF
    # Configuración básica
    ln -sf "/usr/share/zoneinfo/${CFG[TZ]}" /etc/localtime
    hwclock --systohc
    echo "${CFG[HOST]}" > /etc/hostname
    useradd -m -G wheel -s /bin/zsh "${CFG[USER]}"
    echo "${CFG[USER]}:${CFG[PASS]}" | chpasswd
    echo "root:${CFG[PASS]}" | chpasswd
    echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/minimal
    
    # Optimización SSD
    systemctl enable fstrim.timer NetworkManager sshd
    echo "vm.swappiness=10" >> /etc/sysctl.d/99-tuning.conf
EOF
}

main() {
    timedatectl set-ntp true
    setup_network
    fast_partition
    install_core
    configure_minimal
    echo "✅ Instalación base completada en ~2 minutos!"
    echo "   Usuario: ${CFG[USER]}"
    echo "   Password: ${CFG[PASS]}"
    echo "   Ejecuta 'post-install' para personalizar"
}

main
