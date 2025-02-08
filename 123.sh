#!/bin/bash

# Initialize variables
LOG_FILE="install.log"
echo "Starting installation process..." > "$LOG_FILE"

function setup_credentials() {
    echo -n "Enter username: "
    read -e USERNAME
    echo -n "Enter password: "
    read -e PASSWORD

    useradd -m $USERNAME
    echo "$USERNAME:$PASSWORD" | chpasswd
}

function check_uefi() {
    if [[ $(lsmod | grep efivars) ]]; then
        echo "Running in UEFI mode."
    else
        echo "Not running in UEFI mode. This script is designed for UEFI systems."
        exit 1
    fi
}

function detect_hardware() {
    # Basic hardware detection and setup
    lspci | grep -i nvidia && echo "NVIDIA GPU detected."
}

function install_nvidia_drivers() {
    local NVIDIA_REPO="https://download.nvidia.com"

    # Detect NVIDIA GPU model
    local GPU_MODEL=$(lspci | grep -i nvidia)
    if [[ $GPU_MODEL ]]; then
        # Extract driver version from NVIDIA's website
        local DRIVER_VERSION=$(curl -s "$NVIDIA_REPO" | grep -oP 'Linux\ ([0-9.]+)')
        echo "Detected GPU: $GPU_MODEL, installing driver version: $DRIVER_VERSION"

        # Download and install NVIDIA drivers
        cd /tmp || exit
        wget "$NVIDIA_REPO/Xilon/$DRIVER_VERSION/Linux/x86_64/NVIDIA-$DRIVER_VERSION.run"
        chmod +x NVIDIA-*.run
        ./NVIDIA-*-driver.run --accept-eula --no-x-check --install
    else
        echo "No NVIDIA GPU detected. Skipping driver installation."
    fi
}

function configure_grub() {
    # Add GRUB configuration for UEFI
    sed -i 's/GRUB_TIMEOUT=5/GRUB_TIMEOUT=10/g' /etc/default/grub
    update-grub

    # Enable and start necessary services
    systemctl enable ufw
    systemctl start ufw
    ufw default deny
}

function install_ai_packages() {
    # Install Python packages
    pip install numpy pandas scikit-learn tensorflow

    # Verify installation
    echo "Verifying AI package installations..."
    pip list | grep -E 'numpy|pandas|scikit-learn|tensorflow'
}

function main() {
    trap 'echo "Script interrupted. Check $LOG_FILE for details." && exit 1' INT

    echo "Starting Arch Linux automated installation script..." >> "$LOG_FILE"

    # Set keyboard layout
    loadkeys es_es

    # Partition disks (example using cfdisk)
    echo -e "\nPartitioning disks..."
    cfdisk /dev/sda

    # Format partitions and mount
    echo -e "\nFormatting and mounting partitions..."
    mkfs.ext4 /dev/sda1
    mkdir /mnt
    mount /dev/sda1 /mnt

    # Install base system
    echo -e "\nInstalling base system..."
    arch-chroot /mnt
    pacman -Syu --noconfirm

    # Setup user credentials
    setup_credentials

    # Check UEFI mode
    check_uefi

    # Detect hardware and install NVIDIA drivers
    detect_hardware
    install_nvidia_drivers

    # Configure GRUB
    configure_grub

    # Install AI-related packages
    echo -e "\nInstalling AI-related packages..."
    install_ai_packages

    # Finalize installation
    echo -e "\nInstallation completed successfully!"
    echo "Please reboot the system to complete the setup."
}

# Execute main function
main
