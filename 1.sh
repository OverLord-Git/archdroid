#!/bin/bash
# --------------------------------------------
# HybridOS Base Installer (Kernel 6.9+)
# Autor: Chief Architect OS
# --------------------------------------------

# ===== CONFIGURACIÓN INICIAL =====
set -e
LOG_FILE="/var/log/hybridos_base_install.log"
export LC_ALL=en_US.UTF-8

# Función de logging
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOG_FILE
}

# ===== DETECCIÓN DE HARDWARE =====
detect_hardware() {
  if [ -d /sys/firmware/efi ]; then
    BOOT_MODE="uefi"
  else
    BOOT_MODE="bios"
  fi

  if lspci | grep -iq "nvidia"; then
    GPU="nvidia"
  elif lspci | grep -iq "amd"; then
    GPU="amd"
  elif lspci | grep -iq "intel"; then
    GPU="intel"
  else
    GPU="generic"
  fi
  log "Modo de arranque: $BOOT_MODE | GPU detectada: $GPU"
}

# ===== PARTICIONADO =====
partition_disk() {
  DISK=$1
  log "Iniciando particionado en $DISK..."

  # Limpiar disco
  wipefs -a $DISK

  # Esquema para UEFI
  if [ "$BOOT_MODE" = "uefi" ]; then
    parted $DISK mklabel gpt
    parted $DISK mkpart ESP fat32 1MiB 513MiB
    parted $DISK set 1 esp on
    parted $DISK mkpart primary btrfs 513MiB 100%
    PART_BOOT="${DISK}p1"
    PART_ROOT="${DISK}p2"
  else
    # Esquema para BIOS
    parted $DISK mklabel msdos
    parted $DISK mkpart primary ext4 1MiB 513MiB
    parted $DISK set 1 boot on
    parted $DISK mkpart primary btrfs 513MiB 100%
    PART_BOOT="${DISK}1"
    PART_ROOT="${DISK}2"
  fi

  # Formatear particiones
  if [ "$BOOT_MODE" = "uefi" ]; then
    log "Formateando ${PART_BOOT} como FAT32..."
    mkfs.fat -F32 $PART_BOOT
  else
    log "Formateando ${PART_BOOT} como ext4..."
    mkfs.ext4 $PART_BOOT
  fi

  log "Formateando ${PART_ROOT} como Btrfs..."
  mkfs.btrfs -f $PART_ROOT

  log "Particionado completado."
}

# ===== INSTALACIÓN DE PAQUETES =====
install_packages() {
  log "Instalando paquetes base..."
  pacstrap /mnt base base-devel linux-zen linux-zen-headers \
    networkmanager grub efibootmgr git vim

  case $GPU in
    "nvidia")
      pacstrap /mnt nvidia nvidia-utils nvidia-settings
      ;;
    "amd")
      pacstrap /mnt mesa vulkan-radeon
      ;;
    "intel")
      pacstrap /mnt mesa vulkan-intel
      ;;
  esac

  AUDIO=$(whiptail --title "Sistema de Audio" --menu "Elija una opción:" 15 50 4 \
    "1" "PipeWire (Recomendado)" \
    "2" "PulseAudio" 3>&1 1>&2 2>&3)

  if [ "$AUDIO" = "1" ]; then
    pacstrap /mnt pipewire pipewire-pulse pipewire-alsa
  else
    pacstrap /mnt pulseaudio pulseaudio-alsa
  fi
}

# ===== CONFIGURACIÓN POST-INSTALACIÓN =====
configure_system() {
  log "Configurando sistema..."
  genfstab -U /mnt >> /mnt/etc/fstab
  arch-chroot /mnt ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime
  arch-chroot /mnt hwclock --systohc
  echo "en_US.UTF-8 UTF-8" >> /mnt/etc/locale.gen
  arch-chroot /mnt locale-gen
  echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf
  echo "KEYMAP=us" > /mnt/etc/vconsole.conf

  if [ "$BOOT_MODE" = "uefi" ]; then
    arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=HybridOS
  else
    arch-chroot /mnt grub-install --target=i386-pc $DISK
  fi
  arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

  log "Instalación base completada."
}

# ===== EJECUCIÓN PRINCIPAL =====
main() {
  detect_hardware
  DISK=$(whiptail --inputbox "Introduzca el disco a particionar (ej: /dev/nvme0n1):" 10 50 3>&1 1>&2 2>&3)
  partition_disk $DISK
  install_packages
  configure_system
}

main "$@"
