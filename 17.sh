#!/bin/bash

# Configuración inicial del entorno
echo -e "\e[32mActualizando el sistema...\e[0m"
sudo pacman -Syu --noconfirm

# Activación de repositorios adicionales en /etc/pacman.conf
if ! grep -q "^[ ]*[\[]CachyOS[\]]" /etc/pacman.conf; then
    echo -e "\e[32mAgregando repositorio CachyOS...\e[0m"
    sudo tee -a /etc/pacman.conf <<< "[cachyos]
Include = https://raw.githubusercontent.com/cachy-os/cachyos-pacman/master/cachyos.list"

fi

if ! grep -q "^[ ]*[\[]multilib[\]]" /etc/pacman.conf; then
    echo -e "\e[32mAgregando repositorio Multilib...\e[0m"
    sudo tee -a /etc/pacman.conf <<< "[multilib]
Include = https://raw.githubusercontent.com/LinFest/linfest-pacaurio/master/mirrorlist.txt"

fi

# Actualizar los repositories
sudo pacman -Syy --noconfirm

# Instalar herramientas básicas y dependencias
echo -e "\e[32mInstalando dependencias necesarias...\e[0m"
sudo pacman -S python python-pip flatpak yay wine steam android-sdk android-studio --noconfirm

# Configuración de Flatpak
echo -e "\e[32mConfigurando Flatpak...\e[0m"
flatpak install flathub org.gnome.Platform/42 org.kde.Platform/5.26 \
    org.apache.cordova.HelloWorld org.fedoraproject.SimpleApp

# Configuración de DeepSeek y Chatbot en GNOME
echo -e "\e[32mConfigurando DeepSeek...\e[0m"
pip install deepseek-integration

# Creación de usuario y contraseña
while true; do
    echo -e "\e[32mIntroduce el nombre de usuario:\e[0m"
    read -r USERNAME
    if ! id "$USERNAME" >/dev/null 2>&1; then
        break
    fi
    echo -e "\e[31mEl usuario ya existe. Por favor, introduce otro nombre.\e[0m"
done

while true; do
    echo -e "\e[32mIntroduce la contraseña para el usuario $USERNAME:\e[0m"
    read -r PASSWORD
    if [[ "$PASSWORD" != "" ]]; then
        break
    fi
    echo -e "\e[31mLa contraseña no puede estar vacía.\e[0m"
done

sudo useradd -m -p $(openssl passwd -6 -s "$PASSWORD") "$USERNAME"

# Configuración de sudo para el usuario
echo -e "\e[32mConfigurando permisos de sudo...\e[0m"
sudo sh -c "echo \"$USERNAME    ALL=(ALL) ALL\" >> /etc/sudoers"

# Configuración del sistema híbrido Android/Linux
echo -e "\e[32mConfigurando entorno Android/Linux...\e[0m"
sudo android-sdk start-wallet --keypass none

# Configuración de RAID automática si detecta múltiples discos duros
if [ $(lsblk | grep -c disk) -gt 1 ]; then
    echo -e "\e[32mConfigurando RAID...\e[0m"
    # Ejemplo: Configurar un striped volume (ajusta los dispositivos según tus necesidades)
    sudo mdadm --create --verbose /dev/md0 --level=stripe --name="RAID-Striped" \
        --chunk=512 $(lsblk -d | grep disk | awk '{print $1}') 2>/dev/null
fi

# Configuración de autenticación SSH y firewall
echo -e "\e[32mConfigurando seguridad SSH...\e[0m"
sudo systemctl enable sshd --now
sudo ufw allow ssh
sudo ufw default deny incoming
sudo ufw --force enable

# Mensaje final de éxito
echo -e "\e[34mInstalación completada con éxito!\e[0m"
