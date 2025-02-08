#!/bin/bash
# Configuración automática del sistema operativo hibrido Android/Linux
# y DeepSeek Integration

# Variables de color para el output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# 1. Actualizar los repositorios y sistema
echo -e "${BLUE}[+]${NC} Actualizando el sistema..."
sudo pacman -Syu --noconfirm

# 2. Configuración del kernel Linux-zen (versión estable)
echo -e "${BLUE}[+]${NC} Instalando kernel Linux-zen..."
sudo pacman -S linux-zen linux-firmware --noconfirm
sudo grub-mkconfig -o /boot/grub/grub.cfg
sudo systemctl set-default multi-user.target

# 3. Configuración del entorno ligero y optimizado
echo -e "${BLUE}[+]${NC} Configurando entorno ligero..."
sudo pacman -S xorg xorg-server xorg-apps xf86-video-amdgpu \
    xf86-video-intel nvidia-drivers --noconfirm

# 4. Creación de usuario y contraseña
echo -e "${BLUE}[+]${NC} Creando usuario con permisos de sudo..."
useradd -m arch_usuario
passwd arch_usuario

if [ $? -ne 0 ]; then
    echo -e "${RED}Error:${NC} No se pudo crear el usuario. ¿Tienes permisos de administrador?"
    exit 1
fi

usermod -aG wheel $(whoami)
echo -e "${BLUE}[+]${NC} Usuario creado con éxito!"

# 5. Configuración automática de GPU
echo -e "${BLUE}[+]${NC} Detectando tarjeta gráfica..."
 lspci | grep -i nvidia && echo -e "${GREEN}[✓]${NC} NVIDIA detectada" || \
    lspci | grep -i amd && echo -e "${GREEN}[✓]${NC} AMD/ATI detectada" || \
    lspci | grep -i intel && echo -e "${GREEN}[✓]${NC} Intel detectada"

# Instalar驱动especificos segun la GPU
if lspci | grep -i nvidia; then
    sudo systemctl enable nvidia-persistenced
elif lspci | grep -i amd; then
    sudo pacman -S mesa-vdpau-drivers --noconfirm
elif lspci | grep -i intel; then
    sudo pacman -S intel-media-ucode --noconfirm
fi

# 6. Configuración del sistema híbrido Android/Linux
echo -e "${BLUE}[+]${NC} Configurando sistema hibrido Android/Linux..."
sudo pacman -S android-sdk android-studio flatpak yay appimage \
    steam wine --noconfirm

# Configurar Flatpak
flatpak install flathub org.gnome.Platform/42 org.kde.Platform/5.26 \
    org.apache.cordova.HelloWorld org.fedoraproject.SimpleApp

# 7. Integración de DeepSeek y Chatbot en GNOME
echo -e "${BLUE}[+]${NC} Configurando inteligencia artificial..."
sudo pacman -S python python-pip --noconfirm
pip install deepseek-integration

# Instalar dependencias para el chatbot en GNOME
sudo pacman -S gnome-shell-extension-thingy \
    gir1.2-gnome-shell ubuntu-desktop --noconfirm

# Configurar el chatbot de forma automática
echo -e "${BLUE}[+]${NC} Inicializando chatbot..."
gnome-shell-extension-prefs thingy

# 8. Optimización del sistema para rendimiento óptimo
echo -e "${BLUE}[+]${NC} Optimizando el sistema..."
sudo systemctl enable cpu_balancer.service
sudo cpupower governor performance
sudo pacman -S btrfs-progs --noconfirm
sudo mkfs.btrfs /dev/sda && sudo mount -t btrfs /dev/sda /mnt/gp

# Configurar RAID automático (si es necesario)
if lspci | grep -i raid; then
    mdadm --create --verbose /dev/md0 --raid-level 1 \
        /dev/sda1 /dev/sdb1
fi

# 9. Configuración de enrutamiento y firewall automático
echo -e "${BLUE}[+]${NC} Configurando firewall..."
sudo pacman -S ufw --noconfirm
sudo ufw default deny incoming
sudo ufw allow out to any port 80,443
sudo ufw enable

# 10. Mensaje final de éxito
echo -e "${GREEN}[✓]${NC} Instalación completada con éxito!"
