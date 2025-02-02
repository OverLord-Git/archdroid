#!/bin/bash
# ARCHDROID-AI AUTO INSTALLER (v3.0) - FULLY AUTOMATED

# ================= CONFIGURACIÓN INICIAL =================
set -euo pipefail
export LC_ALL=C
trap 'echo "Error fatal en línea $LINENO"; exit 1' ERR

# Configuración Automática
USERNAME="archdroid"
PASSWORD="1"
HOSTNAME="archdroid-ai"
DISK="/dev/nvme0n1"
TIMEZONE="America/Puerto_Rico"
KERNEL="linux-zen"
GPU_VENDOR=$(lspci -nn | grep -E 'VGA|3D' | cut -d '[' -f3 | cut -d ']' -f1)

# ================= FUNCIONES DE INSTALACIÓN =================

partition_disk() {
    parted -s $DISK mklabel gpt
    parted -s $DISK mkpart ESP fat32 1MiB 513MiB
    parted -s $DISK set 1 esp on
    parted -s $DISK mkpart primary 513MiB 100%
    mkfs.fat -F32 -n EFI ${DISK}p1
    cryptsetup luksFormat --batch-mode --verify-passphrase ${DISK}p2 <<< "$PASSWORD"
    cryptsetup open ${DISK}p2 cryptroot <<< "$PASSWORD"
    mkfs.btrfs -L archroot /dev/mapper/cryptroot
    mount -o compress=zstd:1,noatime /dev/mapper/cryptroot /mnt
    mkdir -p /mnt/boot
    mount ${DISK}p1 /mnt/boot
}

install_base() {
    pacstrap /mnt base base-devel $KERNEL $KERNEL-headers linux-firmware \
               btrfs-progs grub grub-btrfs efibootmgr zsh git
}

configure_system() {
    arch-chroot /mnt /bin/bash <<EOF
    ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
    hwclock --systohc
    echo "$HOSTNAME" > /etc/hostname
    sed -i 's/#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
    locale-gen
    echo "LANG=en_US.UTF-8" > /etc/locale.conf
    echo "KEYMAP=us" > /etc/vconsole.conf
    useradd -m -G wheel,audio,video,storage,kvm,libvirt -s /bin/zsh $USERNAME
    echo "$USERNAME:$PASSWORD" | chpasswd
    echo "root:$PASSWORD" | chpasswd
    echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/10-$USERNAME
    chmod 440 /etc/sudoers.d/10-$USERNAME
    systemctl enable NetworkManager.service
EOF
}

configure_bootloader() {
    arch-chroot /mnt /bin/bash <<EOF
    sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect modconf kms keyboard keymap consolefont block encrypt filesystems fsck)/' /etc/mkinitcpio.conf
    mkinitcpio -P $KERNEL
    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=ARCHDROID
    sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"cryptdevice=${DISK}p2:cryptroot root=/dev/mapper/cryptroot mitigations=off nowatchdog\"|" /etc/default/grub
    grub-mkconfig -o /boot/grub/grub.cfg
EOF
}

optimize_system() {
    arch-chroot /mnt /bin/bash <<EOF
    echo "vm.swappiness=10" >> /etc/sysctl.d/99-tuning.conf
    echo "vm.vfs_cache_pressure=50" >> /etc/sysctl.d/99-tuning.conf
    echo "kernel.nmi_watchdog=0" >> /etc/sysctl.d/99-tuning.conf
    echo "ACTION==\"add|change\", KERNEL==\"sd[a-z]|nvme[0-9]n[0-9]\", ATTR{queue/scheduler}=\"mq-deadline\"" > /etc/udev/rules.d/60-iosched.rules
    systemctl enable cpupower.service
    cpupower frequency-set -g performance
EOF
}

install_drivers() {
    arch-chroot /mnt /bin/bash <<EOF
    case "$GPU_VENDOR" in
        "10de") pacman -S --noconfirm nvidia-dkms nvidia-utils lib32-nvidia-utils ;;
        "1002") pacman -S --noconfirm mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon ;;
        "8086") pacman -S --noconfirm mesa lib32-mesa vulkan-intel lib32-vulkan-intel ;;
    esac
    pacman -S --noconfirm vulkan-mesa-layers lib32-vulkan-mesa-layers vkd3d lib32-vkd3d
EOF
}

install_gnome() {
    arch-chroot /mnt /bin/bash <<EOF
    pacman -S --noconfirm gnome gnome-extra gdm
    systemctl enable gdm.service
EOF
}

post_installation() {
    arch-chroot /mnt /bin/bash <<EOF
    systemctl enable fstrim.timer
    firewall-cmd --permanent --zone=public --add-service={http,https}
    firewall-cmd --reload
    pacman -Scc --noconfirm
    rm -rf /var/cache/pacman/pkg/*
    journalctl --vacuum-time=1h
EOF
}

# ================= EJECUCIÓN AUTOMATIZADA =================
main() {
    echo "=== INICIANDO INSTALACIÓN AUTOMÁTICA ==="
    partition_disk
    install_base
    configure_system
    configure_bootloader
    optimize_system
    install_drivers
    install_gnome
    post_installation
    umount -R /mnt
    cryptsetup close cryptroot
    echo "Instalación completada! Reiniciando..."
    reboot
}

main