#!/usr/bin/env bash
# ARCHDROID HYPER INSTALLER v13.0 (VM Ready/Visual)
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
readonly REQUIRED_PACKAGES="git lsb-release sbctl iwd figlet toilet cowsay fortune-mod"

# ================== INICIALIZACIÓN VISUAL ==================
show_banner() {
    clear
    toilet -f future "ARCHDROID" --metal | boxes -d parchment
    fortune | cowsay -n -f $(ls /usr/share/cows | shuf -n1)
    echo
}

step_header() {
    figlet -f slant "$1" | toilet --gay
    echo -e "\n$(date '+%T') - $2" | boxes -d simple
}

# ================== FUNCIONES DE INICIALIZACIÓN ==================
setup_clock() {
    timedatectl set-ntp true
    hwclock --systohc --utc
}

init_system() {
    show_banner
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
        echo "ERROR: Se requiere sistema UEFI" | toilet -f term --gay
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
        step_header "VIRTUALIZACION" "Detectado: ${CFG[VIRTUALIZATION]}"
    fi
}

install_required_packages() {
    step_header "PAQUETES" "Instalando dependencias visuales"
    pacman -Sy --noconfirm --needed $REQUIRED_PACKAGES
}

configure_pacman() {
    sed -i 's/^#Color/Color/' /etc/pacman.conf
    [[ ${CFG[USE_MULTILIB]} -eq 1 ]] && sed -i '/\[multilib\]/,/Include/s/^#//' /etc/pacman.conf
}

# ================== CONFIGURACIÓN INTERACTIVA ==================
setup_interactive() {
    step_header "CONFIGURACION" "Iniciando setup interactivo"
    CFG[DISK]=$(select_disk)
    CFG[USER]=$(read_input "Nombre de usuario: " "archuser")
    CFG[HOST]=$(read_input "Nombre del equipo: " "archdroid")
    
    local pass=$(read_password "Contraseña: ")
    CFG[PASS]="${pass:-$(openssl rand -base64 12)}"
    
    CFG[USE_CACHYOS]=$(confirm "¿Habilitar repositorios CachyOS?")
    CFG[USE_SECUREBOOT]=$(confirm "¿Configurar Secure Boot?")
    CFG[USE_FULLDISK_ENCRYPT]=$(confirm "¿Cifrado completo de disco?")
    
    select_timezone
    select_network
    select_de
    select_gpu
}

# ... (Las funciones select_* se mantienen iguales que la versión anterior)

# ================== CONFIGURACIÓN DEL SISTEMA ==================
secure_partition() {
    step_header "PARTICIONADO" "Configurando disco ${CFG[DISK]}"
    # ... (Implementación anterior igual)
}

install_system() {
    step_header "INSTALACION" "Instalando sistema base"
    local base_packages=(
        base base-devel ${CFG[KERNEL]} ${CFG[KERNEL]}-headers grub efibootmgr 
        networkmanager git zsh reflector flatpak appimagelauncher
        intel-ucode amd-ucode mkinitcpio linux-firmware
    )
    
    [[ "${CFG[VIRTUALIZATION]}" != "none" ]] && base_packages+=(virtualbox-guest-utils open-vm-tools qemu-guest-agent)
    
    pacstrap /mnt "${base_packages[@]}"
    genfstab -U /mnt >> /mnt/etc/fstab
}

secure_configure() {
    step_header "CONFIGURACION" "Aplicando ajustes finales"
    arch-chroot /mnt /bin/bash <<EOF
    # Configuración básica
    ln -sf "/usr/share/zoneinfo/${CFG[TZ_REGION]}/${CFG[TZ_CITY]}" /etc/localtime
    hwclock --systohc
    echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
    locale-gen
    echo "LANG=en_US.UTF-8" > /etc/locale.conf
    echo "${CFG[HOST]}" > /etc/hostname
    
    # Configuración de GRUB mejorada
    echo "GRUB_DEFAULT=saved
GRUB_SAVEDEFAULT=true
GRUB_TIMEOUT=5
GRUB_DISABLE_SUBMENU=y
GRUB_TERMINAL_OUTPUT=console
GRUB_CMDLINE_LINUX_DEFAULT=\"loglevel=3 quiet\"
GRUB_DISABLE_RECOVERY=true" > /etc/default/grub

    if [[ "${CFG[KERNEL]}" != "linux" ]]; then
        sed -i "s/vmlinuz-linux/vmlinuz-${CFG[KERNEL]}/g" /etc/grub.d/10_linux
        sed -i "s/initramfs-linux/initramfs-${CFG[KERNEL]}/g" /etc/grub.d/10_linux
    fi

    # Configuración de virtualización
    case "${CFG[VIRTUALIZATION]}" in
        "vmware") systemctl enable vmtoolsd.service vmware-vmblock-fuse.service ;;
        "oracle") systemctl enable vboxservice.service ;;
        "qemu") systemctl enable qemu-guest-agent ;;
    esac

    # Generación de initramfs
    mkinitcpio -P

    # Instalación de GRUB
    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=ARCHDROID
    grub-mkconfig -o /boot/grub/grub.cfg
    
    # Creación de enlaces seguros
    ln -sf vmlinuz-${CFG[KERNEL]} /boot/vmlinuz-linux
    ln -sf initramfs-${CFG[KERNEL]}.img /boot/initramfs-linux.img
EOF
}

# ... (El resto de funciones se mantienen iguales con step_header agregado)

# ================== EJECUCIÓN PRINCIPAL ==================
main() {
    init_system
    setup_interactive
    secure_partition
    install_system
    secure_configure
    setup_gpu
    setup_desktop
    
    step_header "COMPLETADO" "Instalación Finalizada"
    echo "Usuario: ${CFG[USER]}" | toilet -f term
    echo "Hostname: ${CFG[HOST]}" | boxes -d cat
    echo "Contraseña: ${CFG[PASS]}" | cowsay -n -f dragon
    echo "Reinicia con: systemctl reboot" | figlet -f small
}

main