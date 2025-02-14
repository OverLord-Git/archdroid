#!/bin/bash
# --------------------------------------------
# HybridOS Auto-Installer (Kernel 6.9+)
# Autor: Chief Architect OS
# --------------------------------------------

# ===== CONFIGURACIÓN INICIAL =====
set -e
LOG_FILE="/var/log/hybridos_autoinstall.log"
export LC_ALL=en_US.UTF-8

# Función de logging
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOG_FILE
}

# ===== DETECCIÓN AUTOMÁTICA DE DISCO =====
select_disk() {
  log "Buscando discos disponibles..."
  DISK=$(lsblk -dno NAME,SIZE | grep -Ev 'boot|rpmb|loop' | awk '$2 ~ /G$/ && $2+0 >= 50 {print $1}' | head -1)
  if [ -z "$DISK" ]; then
    log "Error: No se encontró disco con 50GB+ libre"
    exit 1
  fi
  DISK="/dev/$DISK"
  log "Disco seleccionado: $DISK"
}

# ===== PARTICIONADO AUTOMÁTICO =====
auto_partition() {
  log "Limpiando disco..."
  wipefs -af $DISK > /dev/null 2>&1

  if [ -d /sys/firmware/efi ]; then
    log "Creando particiones UEFI..."
    parted $DISK mklabel gpt --script
    parted $DISK mkpart primary fat32 1MiB 513MiB --script
    parted $DISK set 1 esp on --script
    parted $DISK mkpart primary btrfs 513MiB 100% --script
    BOOT_PART="${DISK}1"
    ROOT_PART="${DISK}2"
  else
    log "Creando particiones BIOS..."
    parted $DISK mklabel msdos --script
    parted $DISK mkpart primary ext4 1MiB 513MiB --script
    parted $DISK set 1 boot on --script
    parted $DISK mkpart primary btrfs 513MiB 100% --script
    BOOT_PART="${DISK}1"
    ROOT_PART="${DISK}2"
  fi

  # Formatear
  log "Formateando particiones..."
  if [ -d /sys/firmware/efi ]; then
    mkfs.fat -F32 $BOOT_PART
  else
    mkfs.ext4 $BOOT_PART
  fi
  mkfs.btrfs -f $ROOT_PART > /dev/null

  # Montaje
  mount $ROOT_PART /mnt
  mkdir -p /mnt/boot
  mount $BOOT_PART /mnt/boot
}

# ===== INSTALACIÓN AUTOMÁTICA DE PAQUETES =====
install_base() {
  log "Instalando sistema base..."
  pacstrap /mnt base linux-zen linux-firmware \
    grub efibootmgr networkmanager git \
    gnome gdm gnome-extra gnome-tweaks \
    sudo bash-completion

  # Configuración básica
  genfstab -U /mnt >> /mnt/etc/fstab
  arch-chroot /mnt ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime
  arch-chroot /mnt hwclock --systohc
  echo "en_US.UTF-8 UTF-8" >> /mnt/etc/locale.gen
  arch-chroot /mnt locale-gen
  echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf
}

# ===== CREACIÓN DE USUARIO =====
create_user() {
  log "Creando usuario principal..."
  read -p "Nombre de usuario: " USERNAME
  arch-chroot /mnt useradd -m -G wheel -s /bin/bash $USERNAME
  log "Estableciendo contraseña para $USERNAME:"
  arch-chroot /mnt passwd $USERNAME
  log "Configurando sudo sin contraseña..."
  echo "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" >> /mnt/etc/sudoers
}

# ===== CONFIGURACIÓN FINAL =====
final_setup() {
  log "Instalando GRUB..."
  if [ -d /sys/firmware/efi ]; then
    arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=HYBRIDOS
  else
    arch-chroot /mnt grub-install --target=i386-pc $DISK
  fi
  arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

  log "Habilitando servicios..."
  arch-chroot /mnt systemctl enable gdm networkmanager
}

main() {
  select_disk
  auto_partition
  install_base
  create_user
  final_setup
  log "Instalación base completada! Reinicie y ejecute android_layer.sh"
}

main "$@"
