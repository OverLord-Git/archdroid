#!/system/bin/sh

#!/usr/bin/env bash
# ARCHDROID-AI AUTO INSTALLER PRO (v4.2)
set -euo pipefail
trap 'cleanup && exit 1' ERR

# Configuración Dinámica
declare -A CONFIG=(
    [USER]="archdroid"
    [PASSWORD]="1"
    [HOSTNAME]="archdroid-ai"
    [DISK]="/dev/nvme0n1"
    [TIMEZONE]="America/Puerto_Rico"
    [KERNEL]="linux-zen"
    [FS]="btrfs"
    [LUKS]="true"
    [SECUREBOOT]="true"
    [TPM2]="true"
)

# Constantes
declare -r WORK_DIR="/tmp/archdroid-install"
declare -r LOG_FILE="/var/log/archdroid-install.log"
declare -r COLOR_ERR='\033[1;31m'
declare -r COLOR_OK='\033[1;32m'
declare -r COLOR_RESET='\033[0m'

# Inicialización
init() {
    check_uefi
    detect_hardware
    configure_network
    setup_workdir
    load_tpm_keys
}

check_uefi() {
    [[ -d /sys/firmware/efi/efivars ]] || {
        echo -e "${COLOR_ERR}ERROR: Sistema no UEFI detectado${COLOR_RESET}"
        exit 1
    }
}

detect_hardware() {
    CONFIG[GPU_VENDOR]=$(lspci -nn | grep -E 'VGA|3D' | cut -d '[' -f3 | cut -d ']' -f1)
    CONFIG[CPU_VENDOR]=$(grep -m1 vendor_id /proc/cpuinfo | cut -d: -f2 | tr -d ' ')
    CONFIG[RAM_GB]=$(free -g | awk '/Mem:/ {print $2}')
}

configure_network() {
    if ! ping -c1 archlinux.org &> /dev/null; then
        echo -e "${COLOR_OK}Configurando conexión de emergencia...${COLOR_RESET}"
        systemctl start iwd dhcpcd
        iwctl station wlan0 connect "${WIFI_SSID}" password "${WIFI_PASS}"
    fi
}

setup_workdir() {
    mkdir -p "$WORK_DIR"
    exec 3>&1 4>&2
    exec > >(tee -a "$LOG_FILE") 2>&1
}

cleanup() {
    [[ -d "$WORK_DIR" ]] && rm -rf "$WORK_DIR"
    exec 1>&3 2>&4
}

# Cifrado y Seguridad
setup_crypt() {
    local disk_part="${CONFIG[DISK]}p2"
    
    if [[ "${CONFIG[LUKS]}" == "true" ]]; then
        if [[ "${CONFIG[TPM2]}" == "true" ]]; then
            echo -e "${COLOR_OK}Configurando LUKS2 con TPM2...${COLOR_RESET}"
            cryptsetup luksFormat --type luks2 --pbkdf=argon2id --iter-time=4000 "$disk_part" <<< "${CONFIG[PASSWORD]}"
            systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0,1,2,3,4,5,7 "$disk_part"
        else
            cryptsetup luksFormat --type luks2 --pbkdf=argon2id "$disk_part" <<< "${CONFIG[PASSWORD]}"
        fi
        
        cryptsetup open "$disk_part" cryptroot <<< "${CONFIG[PASSWORD]}"
        CONFIG[ROOT_DEV]="/dev/mapper/cryptroot"
    else
        CONFIG[ROOT_DEV]="$disk_part"
    fi
}

# Particionado Inteligente
partition_disk() {
    local boot_part="${CONFIG[DISK]}p1"
    local root_part="${CONFIG[DISK]}p2"
    
    parted -s "${CONFIG[DISK]}" mklabel gpt
    parted -s "${CONFIG[DISK]}" mkpart ESP fat32 1MiB 513MiB
    parted -s "${CONFIG[DISK]}" set 1 esp on
    parted -s "${CONFIG[DISK]}" mkpart primary 513MiB 100%
    
    mkfs.fat -F32 -n ARCHBOOT "$boot_part"
    
    if [[ "${CONFIG[FS]}" == "btrfs" ]]; then
        mkfs.btrfs -L ARCHROOT -f "${CONFIG[ROOT_DEV]}"
        mount -o compress=zstd:1,noatime "${CONFIG[ROOT_DEV]}" /mnt
    else
        mkfs.ext4 -L ARCHROOT "${CONFIG[ROOT_DEV]}"
        mount "${CONFIG[ROOT_DEV]}" /mnt
    fi
    
    mkdir -p /mnt/boot
    mount "$boot_part" /mnt/boot
}

# Instalación Optimizada
install_base() {
    local packages=(base base-devel "${CONFIG[KERNEL]}" "${CONFIG[KERNEL]}"-headers linux-firmware 
                   btrfs-progs grub grub-btrfs efibootmgr zsh git reflector)
    
    (( CONFIG[RAM_GB] < 16 )) && packages+=(zram-generator)
    
    pacstrap /mnt "${packages[@]}"
    genfstab -U /mnt >> /mnt/etc/fstab
}

configure_system() {
    arch-chroot /mnt /bin/bash <<EOF
    # Configuración básica
    ln -sf "/usr/share/zoneinfo/${CONFIG[TIMEZONE]}" /etc/localtime
    hwclock --systohc
    echo "${CONFIG[HOSTNAME]}" > /etc/hostname
    
    # Locales
    sed -i 's/#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
    locale-gen
    echo "LANG=en_US.UTF-8" > /etc/locale.conf
    
    # Usuario y seguridad
    useradd -m -G wheel,audio,video,storage,kvm,libvirt -s /bin/zsh "${CONFIG[USER]}"
    echo "${CONFIG[USER]}:${CONFIG[PASSWORD]}" | chpasswd
    echo "root:${CONFIG[PASSWORD]}" | chpasswd
    echo "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/10-archdroid
    
    # Optimización del sistema
    systemctl enable NetworkManager fstrim.timer systemd-oomd
    echo "kernel.nmi_watchdog=0" >> /etc/sysctl.d/99-tuning.conf
EOF
}

# Configuración Avanzada
setup_bootloader() {
    arch-chroot /mnt /bin/bash <<EOF
    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=ARCHDROID
    sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"cryptdevice=${CONFIG[DISK]}p2:cryptroot root=${CONFIG[ROOT_DEV]} nowatchdog mitigations=off\"|" /etc/default/grub
    
    if [[ "${CONFIG[SECUREBOOT]}" == "true" ]]; then
        pacman -S --noconfirm sbctl
        sbctl create-keys
        sbctl enroll-keys -m
        sbctl sign -s /boot/EFI/ARCHDROID/grubx64.efi
    fi
    
    grub-mkconfig -o /boot/grub/grub.cfg
EOF
}

# Optimización de Hardware
tune_system() {
    case "${CONFIG[CPU_VENDOR]}" in
        "GenuineIntel")
            arch-chroot /mnt /bin/bash <<EOF
            pacman -S --noconfirm intel-ucode intel-gpu-tools
            echo "options i915 enable_guc=3" > /etc/modprobe.d/i915.conf
EOF
            ;;
        "AuthenticAMD")
            arch-chroot /mnt /bin/bash <<EOF
            pacman -S --noconfirm amd-ucode
            echo "options amdgpu ppfeaturemask=0xffffffff" > /etc/modprobe.d/amdgpu.conf
            echo "options amd_pstate=guided" > /etc/modprobe.d/amd_pstate.conf
EOF
            ;;
    esac

    # GPU específica
    case "${CONFIG[GPU_VENDOR]}" in
        "10de") setup_nvidia ;;
        "1002") setup_amd ;;
        "8086") setup_intel ;;
    esac
}

setup_nvidia() {
    arch-chroot /mnt /bin/bash <<EOF
    pacman -S --noconfirm nvidia-dkms nvidia-utils lib32-nvidia-utils nvidia-settings
    echo "options nvidia-drm modeset=1" > /etc/modprobe.d/nvidia.conf
    echo "blacklist nouveau" > /etc/modprobe.d/blacklist.conf
EOF
}

# Instalación de Componentes Principales
install_gnome() {
    arch-chroot /mnt /bin/bash <<EOF
    pacman -S --noconfirm gnome gnome-extra gdm
    systemctl enable gdm
EOF
}

setup_ai_stack() {
    arch-chroot /mnt /bin/bash <<EOF
    sudo -u "${CONFIG[USER]}" yay -S --noconfirm deepseek-coder-bin
    mkdir -p /opt/ai/models
    wget https://models.deepseek.ai/archdroid/llm-v3.gguf -O /opt/ai/models/main.gguf
    chown -R "${CONFIG[USER]}":"${CONFIG[USER]}" /opt/ai
    
    cat > /etc/systemd/system/deepseek-ai.service <<'END'
[Unit]
Description=DeepSeek AI Assistant
After=network.target

[Service]
User=${CONFIG[USER]}
ExecStart=/usr/bin/deepseek --model /opt/ai/models/main.gguf --ctx-size 4096
Restart=always

[Install]
WantedBy=multi-user.target
END

    systemctl enable deepseek-ai
EOF
}

# Post-Instalación
finalize() {
    umount -R /mnt
    [[ "${CONFIG[LUKS]}" == "true" ]] && cryptsetup close cryptroot
    echo -e "${COLOR_OK}Instalación completada! Reiniciando...${COLOR_RESET}"
    reboot
}

# Flujo Principal
main() {
    init
    setup_crypt
    partition_disk
    install_base
    configure_system
    setup_bootloader
    tune_system
    install_gnome
    setup_ai_stack
    finalize
}

main "$@"