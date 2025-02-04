#!/usr/bin/env bash
# ARCHDROID HYPER INSTALLER v13.2 (No Dependencies)
set -euo pipefail
trap 'cleanup && exit 1' ERR

# Configuración Dinámica
declare -A CFG=(
    [USER]=""                 [HOST]="archdroid"
    [DISK]=""                 [TZ_REGION]="America"
    [TZ_CITY]="New_York"      [KERNEL]="linux-zen"
    [FS]="btrfs"              [DE]="gnome"
    [GPU_TYPE]="auto"         [MODE]="desktop"
    [USE_CACHYOS]="0"         [USE_MULTILIB]="1"
    [USE_SECUREBOOT]="0"      [USE_FULLDISK_ENCRYPT]="1"
    [AI_MODEL]="deepseek-7b-Q8_0"
    [VIRTUALIZATION]="none"
)

# Constantes
readonly MIRRORLIST_URL="https://archlinux.org/mirrorlist/all/"
readonly AI_MODEL_CHECKSUM="a1b2c3d4e5f6..."
readonly REQUIRED_PACKAGES="git lsb-release sbctl iwd"

# ================== FUNCIONES DE INICIALIZACIÓN ==================
show_header() {
    clear
    echo -e "\e[1;34m"
    echo " █████╗ ██████╗  ██████╗██╗  ██╗██████╗ ██████╗ ██████╗ ██╗██████╗ "
    echo "██╔══██╗██╔══██╗██╔════╝██║  ██║██╔══██╗██╔══██╗██╔══██╗██║██╔══██╗"
    echo "███████║██████╔╝██║     ███████║██║  ██║██████╔╝██║  ██║██║██║  ██║"
    echo "██╔══██║██╔══██╗██║     ██╔══██║██║  ██║██╔══██╗██║  ██║██║██║  ██║"
    echo "██║  ██║██║  ██║╚██████╗██║  ██║██████╔╝██║  ██║██████╔╝██║██████╔╝"
    echo "╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝╚═════╝ ╚═╝  ╚═╝╚═════╝ ╚═╝╚═════╝ "
    echo -e "\e[0m"
    echo -e "\e[33mInstalador Automático de Arch Linux - Versión 13.2\e[0m"
    echo "=============================================================="
}

step_header() {
    echo -e "\n\e[1;36m[$1] $2\e[0m"
    echo "--------------------------------------------------------------"
}

init_system() {
    show_header
    check_uefi
    setup_clock
    loadkeys us
    detect_virtualization
    verify_internet
    install_required_packages
    configure_pacman
    setup_mirrors
}

check_uefi() {
    [[ -d /sys/firmware/efi ]] || {
        echo -e "\e[31m[ERROR] Se requiere sistema UEFI\e[0m"
        exit 1
    }
}

detect_virtualization() {
    if [[ $(systemd-detect-virt) != "none" ]]; then
        CFG[VIRTUALIZATION]=$(systemd-detect-virt)
        case "${CFG[VIRTUALIZATION]}" in
            "vmware")    CFG[KERNEL]="linux" ;;
            "oracle")    CFG[KERNEL]="linux-lts" ;;
            "qemu")      CFG[KERNEL]="linux" ;;
        esac
        step_header "VIRTUALIZACIÓN" "Detectado: ${CFG[VIRTUALIZATION]}"
    fi
}

install_required_packages() {
    step_header "PAQUETES" "Instalando dependencias básicas"
    pacman -Sy --noconfirm --needed $REQUIRED_PACKAGES
}

configure_pacman() {
    sed -i 's/^#Color/Color/' /etc/pacman.conf
    [[ ${CFG[USE_MULTILIB]} -eq 1 ]] && sed -i '/\[multilib\]/,/Include/s/^#//' /etc/pacman.conf
}

# ... (Las funciones select_* y de particionado se mantienen iguales)

# ================== EJECUCIÓN PRINCIPAL ==================
main() {
    init_system
    setup_interactive
    secure_partition
    install_system
    secure_configure
    setup_gpu
    setup_desktop
    
    echo -e "\n\e[1;32m[COMPLETADO] Instalación Finalizada\e[0m"
    echo -e "\e[33mUsuario:\e[0m ${CFG[USER]}"
    echo -e "\e[33mHostname:\e[0m ${CFG[HOST]}"
    echo -e "\e[33mContraseña:\e[0m ${CFG[PASS]}"
    echo -e "\e[33mReinicia con:\e[0m systemctl reboot\n"
}

main