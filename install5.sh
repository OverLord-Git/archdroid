#!/usr/bin/env bash
# ARCHDROID ULTIMATE INSTALLER (v5.0) - Steam/Android/AI/Flatpak
set -eo pipefail

# Configuración básica
USER="archuser"             PASS="1"           HOST="archdroid"
DISK="/dev/nvme0n1"         TZ="America/Puerto_Rico"  LANG="en_US.UTF-8"
KERNEL="linux-zen"          FS="btrfs"         GPU=$(lspci -nn | grep -E 'VGA|3D')

# Paquetes esenciales
BASE_PKGS=(base base-devel $KERNEL linux-firmware grub efibootmgr networkmanager 
           git zsh flatpak appimagelauncher)
GPU_PKGS=(vulkan-radeon vulkan-intel nvidia-dkms lib32-nvidia-utils)
AI_PKGS=(python-pytorch python-tensorflow jupyter-notebook deepseek-coder)
ANDROID_PKGS=(waydroid python-pyclip)
STEAM_PKGS=(steam lib32-vulkan-radeon lib32-vulkan-intel)

# Funciones principales
init_system() {
    timedatectl set-ntp true
    loadkeys la-latin1
    [[ -d /sys/firmware/efi ]] || { echo "Solo UEFI!"; exit 1; }
}

partition_disk() {
    parted -s $DISK mklabel gpt
    parted -s $DISK mkpart ESP fat32 1MiB 513MiB set 1 esp on
    parted -s $DISK mkpart primary 513MiB 100%
    mkfs.fat -F32 ${DISK}p1
    cryptsetup luksFormat ${DISK}p2 <<< "$PASS"
    cryptsetup open ${DISK}p2 cryptroot <<< "$PASS"
    mkfs.$FS -L root /dev/mapper/cryptroot
    mount /dev/mapper/cryptroot /mnt
    mkdir -p /mnt/boot && mount ${DISK}p1 /mnt/boot
}

install_base() {
    pacstrap /mnt ${BASE_PKGS[@]} ${GPU_PKGS[@]}
    genfstab -U /mnt >> /mnt/etc/fstab
}

configure_system() {
    arch-chroot /mnt /bin/bash <<EOF
    ln -sf /usr/share/zoneinfo/$TZ /etc/localtime
    hwclock --systohc
    echo $LANG > /etc/locale.conf
    echo "$HOST" > /etc/hostname
    useradd -m -G wheel -s /bin/zsh $USER
    echo "$USER:$PASS" | chpasswd
    echo "root:$PASS" | chpasswd
    sed -i 's/# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/%wheel ALL=(ALL:ALL) NOPASSWD: ALL/' /etc/sudoers
EOF
}

setup_drivers() {
    case "$GPU" in
        *NVIDIA*) arch-chroot /mnt nvidia-modprobe ;;
        *AMD*) echo "options amdgpu ppfeaturemask=0xffffffff" > /mnt/etc/modprobe.d/amdgpu.conf ;;
        *Intel*) echo "options i915 enable_guc=3" > /mnt/etc/modprobe.d/i915.conf ;;
    esac
}

install_extras() {
    arch-chroot /mnt /bin/bash <<EOF
    # Android
    pacman -S --noconfirm ${ANDROID_PKGS[@]}
    systemctl enable waydroid-container
    waydroid init -s GAPPS

    # Steam Gaming
    pacman -S --noconfirm ${STEAM_PKGS[@]} 
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

    # AI Stack
    pacman -S --noconfirm ${AI_PKGS[@]}
    pip install transformers langchain
    wget https://models.deepseek.ai/archdroid-base.q8_0.gguf -O /opt/ai_model.gguf

    # AppImage Integration
    echo 'alias apprun="appimagelauncher --no-sandbox"' >> /home/$USER/.zshrc
EOF
}

finalize() {
    arch-chroot /mnt /bin/bash <<EOF
    grub-install --target=x86_64-efi --efi-directory=/boot
    sed -i "s|GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"cryptdevice=${DISK}p2:cryptroot\"|" /etc/default/grub
    grub-mkconfig -o /boot/grub/grub.cfg
    systemctl enable gdm NetworkManager
EOF
}

# Flujo principal
init_system
partition_disk
install_base
configure_system
setup_drivers
install_extras
finalize

umount -R /mnt
cryptsetup close cryptroot
echo "Instalación completada! Reiniciando..."
reboot
