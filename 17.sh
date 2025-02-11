#!/bin/bash
set -euo pipefail

# --- Configuración de colores ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# --- Detección de hardware ---
echo -e "${YELLOW}→ Detectando modo de arranque...${NC}"
if [ -d /sys/firmware/efi ]; then
  BOOT_MODE="UEFI"
else
  BOOT_MODE="BIOS"
fi
echo -e "Modo detectado: ${GREEN}${BOOT_MODE}${NC}"

# --- Selección de disco ---
echo -e "${YELLOW}→ Discos disponibles:${NC}"
lsblk -d -o NAME,SIZE,TYPE,MODEL | grep -E 'disk|nvme'
read -p "Introduce el dispositivo (ej: nvme0n1, sda): " DISK

# Validar disco NVMe
if [[ "$DISK" =~ ^nvme ]]; then
  DISK_PATH="/dev/${DISK}p"
else
  DISK_PATH="/dev/${DISK}"
fi

# --- Cifrado LUKS (opcional) ---
read -p "¿Cifrar disco? (s/n): " USE_LUKS
if [[ "$USE_LUKS" == "s" ]]; then
  echo -e "${YELLOW}→ Configurando LUKS...${NC}"
  cryptsetup luksFormat "${DISK_PATH}2"
  cryptsetup open "${DISK_PATH}2" archdroid_crypt
  ROOT_PART="/dev/mapper/archdroid_crypt"
else
  ROOT_PART="${DISK_PATH}2"
fi

# --- Particionado ---
echo -e "${YELLOW}→ Creando particiones...${NC}"
if [[ "$BOOT_MODE" == "UEFI" ]]; then
  parted -s "/dev/$DISK" mklabel gpt
  parted -s "/dev/$DISK" mkpart ESP fat32 1MiB 513MiB
  parted -s "/dev/$DISK" set 1 esp on
  parted -s "/dev/$DISK" mkpart primary ext4 513MiB 100%
  mkfs.fat -F32 "${DISK_PATH}1"
  mkfs.ext4 -F "$ROOT_PART"
  mount "$ROOT_PART" /mnt
  mkdir -p /mnt/boot/efi
  mount "${DISK_PATH}1" /mnt/boot/efi
else
  parted -s "/dev/$DISK" mklabel msdos
  parted -s "/dev/$DISK" mkpart primary ext4 1MiB 100%
  parted -s "/dev/$DISK" set 1 boot on
  mkfs.ext4 "${DISK_PATH}1"
  mount "${DISK_PATH}1" /mnt
fi

# --- Instalación base ---
echo -e "${YELLOW}→ Instalando sistema base...${NC}"
pacstrap /mnt base sudo linux-zen linux-zen-headers linux-firmware git

# --- Configuración post-instalación ---
echo -e "${YELLOW}→ Configurando sistema...${NC}"
genfstab -U /mnt >> /mnt/etc/fstab

# --- Creación interactiva de usuario ---
read -p "Introduce el nombre de usuario: " USERNAME
arch-chroot /mnt useradd -m -G wheel "$USERNAME"
echo -e "${YELLOW}→ Estableciendo contraseña para $USERNAME...${NC}"
arch-chroot /mnt passwd "$USERNAME"

# --- Configurar sudo sin contraseña ---
echo -e "${YELLOW}→ Configurando privilegios sudo...${NC}"
echo '%wheel ALL=(ALL) NOPASSWD: ALL' | tee /mnt/etc/sudoers.d/10-wheel-nopasswd > /dev/null
chmod 440 /mnt/etc/sudoers.d/10-wheel-nopasswd

# --- Instalar yay como usuario normal ---
echo -e "${YELLOW}→ Instalando yay desde AUR...${NC}"
arch-chroot /mnt sudo -u "$USERNAME" git clone https://aur.archlinux.org/yay.git /home/"$USERNAME"/yay
arch-chroot /mnt bash -c "cd /home/$USERNAME/yay && sudo -u $USERNAME makepkg -si --noconfirm"

# --- Paquetes principales ---
echo -e "${YELLOW}→ Instalando componentes del sistema...${NC}"
arch-chroot /mnt yay -Syu --noconfirm --needed \
  calamares gnome gnome-tweaks gnome-shell-extensions \
  waydroid mesa vulkan-intel flatpak appimagelauncher \
  zram-generator tensorflow python-rasa

# --- Configurar GNOME ---
echo -e "${YELLOW}→ Personalizando entorno GNOME...${NC}"
arch-chroot /mnt sudo -u "$USERNAME" dbus-launch gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark'
arch-chroot /mnt sudo -u "$USERNAME" dbus-launch gsettings set org.gnome.shell.extensions.dash-to-panel panel-position 'BOTTOM'
arch-chroot /mnt sudo -u "$USERNAME" dbus-launch gsettings set org.gnome.shell.extensions.arc-menu menu-layout 'Eleven'

# --- Configurar Android ---
echo -e "${YELLOW}→ Habilitando soporte para Android...${NC}"
echo "binder_linux" | tee /mnt/etc/modules-load.d/binder.conf > /dev/null
echo "loop" | tee /mnt/etc/modules-load.d/loop.conf > /dev/null

# --- Optimización de memoria ---
echo -e "${YELLOW}→ Configurando zRAM...${NC}"
arch-chroot /mnt systemctl enable systemd-zram-setup@zram0
echo "vm.swappiness=10" | tee /mnt/etc/sysctl.d/99-archdroid.conf > /dev/null

# --- Instalar GRUB ---
echo -e "${YELLOW}→ Configurando gestor de arranque...${NC}"
if [[ "$BOOT_MODE" == "UEFI" ]]; then
  arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot/efi
else
  arch-chroot /mnt grub-install --target=i386-pc "/dev/$DISK"
fi
arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

# --- Google Play Store (opcional) ---
read -p "¿Instalar Google Play Store? (s/n): " USE_GAPPS
if [[ "$USE_GAPPS" == "s" ]]; then
  echo -e "${YELLOW}→ Configurando Waydroid con GAPPS...${NC}"
  arch-chroot /mnt yay -S --noconfirm waydroid-models
  arch-chroot /mnt waydroid init -s GAPPS -f
fi

# --- Limpieza final ---
echo -e "${YELLOW}→ Eliminando archivos temporales...${NC}"
arch-chroot /mnt yay -Scc --noconfirm
rm -rf /mnt/home/"$USERNAME"/yay

echo -e "\n${GREEN}✓ Instalación completada. Reinicia con: 'reboot'${NC}"
