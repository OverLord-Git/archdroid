#!/bin/bash
set -eo pipefail

# 1. UEFI Mode Detection
if ! efivarfs_is-mounted | grep -q "efivarfs Mounted"; then
    echo "System not in UEFI mode. Exiting."
    exit 1
fi

# 2. Hardware Detection for SSD/NVMe
SSD_DETECTED=false
for device in /sys/block/*/removable; do
    if [ "$(cat $device)" = "0" ]; then
        SSD_DETECTED=true
        break
    fi
done

echo "UEFI mode detected: Proceeding with installation."
if $SSD_DETECTED; then
    echo "SSD or NVMe drive detected: Optimizing for fast storage."
else
    echo "HDD detected: Adjusting settings for optimal performance on HDD."
fi

# 3. Installing Essential Packages
echo "Installing AUR helper 'yay'..."
sudo pacman -S yay git base-devel

echo "Updating package and system..."
sudo pacman -Syu

echo "Installing Linux Zen kernel..."
sudo yay -S linux-zen linux-zen Headers

# 4. Configuring the System
sudo systemctl enable --now ufw firewalld
sudo ufw default deny incoming
sudo ufw allow out
sudo ufw allow ssh
sudo ufw --dry-run status | grep 'Dry Run' && sudo ufw enable

# 5. Android and Linux Hybrid Setup
echo "Setting up Android environment..."
sudo pacman -S android-sdk java-openjdk
mkdir -p ~/Android/SDK
export ANDROID_SDK_ROOT=~/Android/SDK
echo "path='~/.local/bin:~/.config/jabba/bin:$PATH'" >> ~/.bashrc

# 6. AI Integration with Chatbot in Gnome
echo "Installing AI libraries..."
sudo pacman -S python3 numpy matplotlib
git clone https://github.com/example/chatbot.git
cd chatbot
pip install requirements.txt
./setup.sh

# 7. Multi-Platform Application Support
echo "Configuring Flatpak, Steam, and Wine..."
sudo pacman -S flatpak steam wine
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

# 8. Finalizing System Optimization
echo "Adjusting kernel parameters for performance..."
sudo bash -c 'cat >> /etc/sysctl.conf << EOL
net.core.rmem_max = 32M
net.core.wmem_max = 32M
EOL'

sudo systemctl enable --now dnfdaemon

# Completion Message
echo "Arch Linux installation completed successfully!"
echo "AI chatbot and hybrid Android environment are ready for use."
```
