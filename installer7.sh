#!/usr/bin/env bash
# ARCHDROID HYBRID INSTALLER v7.0 (Mobile Ready)
set -eo pipefail
trap 'echo "Error en línea $LINENO"; exit 1' ERR

# Configuración Global
export LANG=en_US.UTF-8
declare -A CFG=(
    [USER]="mobileuser"
    [PASS]="$(openssl rand -base64 12)"
    [HOST]="archdroid-mobile"
    [DISK]="/dev/nvme0n1"
    [TZ]="America/New_York"
    [KERNEL]="linux-zen"
    [FS]="btrfs"
    [GPU]="$(lspci -nn | grep -E 'VGA|3D')"
)

# Repositorios y Paquetes
declare -a MIRRORS=(
    "https://mirror.cachyos.org/repo/x86_64/cachyos"
    "https://mirror.cachyos.org/repo/x86_64/cachyos-extra"
)

declare -a PKGS=(
    base base-devel linux-zen linux-zen-headers git reflector
    nvidia-dkms nvidia-utils lib32-nvidia-utils vulkan-icd-loader
    waydroid python-pyclip flatpak appimagelauncher yay
    plasma-mobile plasma-nm plasma-pa pipewire phonon-qt5-gstreamer
    ofono phosh calls chatty kgx
)

# Configuración Inicial
setup_environment() {
    timedatectl set-ntp true
    loadkeys us
    reflector --latest 20 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
    
    # Habilitar multilib y repositorios CachyOS
    sed -i 's/#\[multilib\]/\[multilib\]/;s/#Include = \/etc\/pacman.d\/mirrorlist/Include = \/etc\/pacman.d\/mirrorlist/' /etc/pacman.conf
    for repo in "${MIRRORS[@]}"; do
        echo -e "\n[cachyos]\nServer = $repo" >> /etc/pacman.conf
    done
    
    pacman-key --recv-keys F3B607488DB35A47 --keyserver keyserver.ubuntu.com
    pacman-key --lsign-key F3B607488DB35A47
    pacman -Sy
}

# Particionado para Dispositivos Móviles
partition_disk() {
    parted -s ${CFG[DISK]} mklabel gpt
    parted -s ${CFG[DISK]} mkpart ESP fat32 1MiB 513MiB set 1 esp on
    parted -s ${CFG[DISK]} mkpart primary 513MiB 100%
    
    mkfs.fat -F32 ${CFG[DISK]}p1
    cryptsetup luksFormat --type luks2 ${CFG[DISK]}p2 <<< "${CFG[PASS]}"
    cryptsetup open ${CFG[DISK]}p2 cryptroot <<< "${CFG[PASS]}"
    
    mkfs.btrfs -L ROOT -M /dev/mapper/cryptroot
    mount /dev/mapper/cryptroot /mnt
    mkdir -p /mnt/boot && mount ${CFG[DISK]}p1 /mnt/boot
}

# Instalación Base
install_system() {
    pacstrap /mnt ${PKGS[@]}
    genfstab -U /mnt >> /mnt/etc/fstab
}

# Configuración del Sistema
configure_system() {
    arch-chroot /mnt /bin/bash <<EOF
    ln -sf /usr/share/zoneinfo/${CFG[TZ]} /etc/localtime
    hwclock --systohc
    sed -i 's/#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
    locale-gen
    echo "LANG=en_US.UTF-8" > /etc/locale.conf
    echo "KEYMAP=us" > /etc/vconsole.conf
    echo "${CFG[HOST]}" > /etc/hostname
    
    useradd -m -G wheel,network,video,audio,storage,rfkill,sys,input -s /bin/zsh ${CFG[USER]}
    echo "${CFG[USER]}:${CFG[PASS]}" | chpasswd
    echo "root:${CFG[PASS]}" | chpasswd
    echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/10-mobile
    
    systemctl enable NetworkManager fstrim.timer systemd-oomd bluetooth
EOF
}

# Configuración Mobile
setup_mobile() {
    arch-chroot /mnt /bin/bash <<EOF
    # Waydroid con aceleración GPU
    systemctl enable waydroid-container
    waydroid init -s GAPPS
    
    # Configuración Phosh
    sudo -u ${CFG[USER]} mkdir -p /home/${CFG[USER]}/.config/autostart
    echo -e "[Desktop Entry]\nType=Application\nName=Phosh\nExec=phosh" > /home/${CFG[USER]}/.config/autostart/phosh.desktop
    
    # Reglas udev para dispositivos móviles
    echo 'SUBSYSTEM=="power_supply", ENV{POWER_SUPPLY_ONLINE}=="0", RUN+="/usr/bin/systemctl suspend"' > /etc/udev/rules.d/99-low-battery.rules
    
    # Optimización para ARM emulation
    echo "binfmt_misc" > /etc/modules-load.d/binfmt.conf
    systemctl restart systemd-binfmt
EOF
}

# Finalización
finalize() {
    arch-chroot /mnt /bin/bash <<EOF
    grub-install --target=x86_64-efi --efi-directory=/boot
    sed -i "s|GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"cryptdevice=${CFG[DISK]}p2:cryptroot fbcon=rotate:1\"|" /etc/default/grub
    grub-mkconfig -o /boot/grub/grub.cfg
    
    # Rotación automática de pantalla
    echo "SUBSYSTEM==\"drm\", ACTION==\"change\", RUN+=\"/usr/bin/gsd-orientation\"" > /etc/udev/rules.d/61-screen-rotation.rules
EOF

    umount -R /mnt
    cryptsetup close cryptroot
    echo "Instalación completada!"
    echo "Usuario: ${CFG[USER]}"
    echo "Password: ${CFG[PASS]}"
    reboot
}

# Flujo Principal
setup_environment
partition_disk
install_system
configure_system
setup_mobile
finalize
