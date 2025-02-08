#!/bin/bash

# AndroNix-OS Creator - Versión Estable Final
# Licencia: GPLv3

check_uefi() {
    [ ! -d /sys/firmware/efi ] && echo "ERROR: Se requiere UEFI!" && exit 1
}

detect_hardware() {
    DISK=$(lsblk -dno NAME -e 7,11 | grep -E 'nvme|sda|mmc' | head -1)
    SSD=$(lsblk -d -o rota /dev/$DISK | grep -w 0 && SSD_OPTIONS="discard,noatime")
    RAM=$(grep MemTotal /proc/meminfo | awk '{print $2}')
}

partition_setup() {
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
    pacstrap /mnt base linux-zen linux-zen-headers linux-firmware \
              base-devel git reflector networkmanager \
              python python-pip xorg-server gnome bash zram-generator
}

configure_system() {
    genfstab -U /mnt >> /mnt/etc/fstab
    [ -n "$SSD_OPTIONS" ] && sed -i "s|relatime|$SSD_OPTIONS|g" /mnt/etc/fstab

    arch-chroot /mnt bash -c '
        # Habilitar repos multilib
        sed -i "/\[multilib\]/,/Include/"'!'"'s/^#//' /etc/pacman.conf
        pacman -Sy

        # Configurar usuario
        useradd -m -G wheel -s /bin/bash user
        echo "password" | passwd --stdin user
        echo -e "\nuser ALL=(ALL) ALL" >> /etc/sudoers

        # Instalar yay como usuario normal
        su - user -c "
            git clone https://aur.archlinux.org/yay.git
            cd yay
            makepkg -si --noconfirm
            cd ..
            rm -rf yay
        "

        # Instalar paquetes esenciales
        pacman -S --noconfirm flatpak wine-staging steam lib32-mesa \
                  noto-fonts-cjk noto-fonts-emoji

        # Instalar Waydroid desde AUR
        su - user -c "yay -S --noconfirm waydroid python-pytorch python-tensorflow"

        # Configurar Python y IA
        pip install --break-system-packages \
            onnxruntime chatterbot transformers spacy[cuda]

        # Configurar servicio Waydroid
        su - user -c "waydroid init"
        cat > /etc/systemd/system/waydroid.service <<EOF
[Unit]
Description=Waydroid Container Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/waydroid container start
ExecStop=/usr/bin/waydroid container stop
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

        # Habilitar servicios
        systemctl enable NetworkManager
        systemctl enable gdm
        systemctl enable waydroid
    '
}

post_install() {
    # Configurar ZRAM
    mkdir -p /mnt/etc/systemd/
    echo "[zram0]" > /mnt/etc/systemd/zram-generator.conf
    echo "zram-size = ram / 2" >> /mnt/etc/systemd/zram-generator.conf

    # Optimizaciones de kernel
    mkdir -p /mnt/etc/sysctl.d/
    echo "vm.swappiness=10" > /mnt/etc/sysctl.d/99-optimization.conf
    echo "vm.vfs_cache_pressure=50" >> /mnt/etc/sysctl.d/99-optimization.conf
}

main() {
    check_uefi
    detect_hardware
    partition_setup
    install_base
    configure_system
    post_install
    umount -R /mnt
    echo "Instalación completada! Usuario: 'user' - Contraseña: 'password'"
}

main
