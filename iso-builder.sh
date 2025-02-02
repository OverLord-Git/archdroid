#!/usr/bin/env bash
# ARCHDROID-AI ISO BUILDER PRO (v4.0)
set -eo pipefail
trap 'handle_error $LINENO' ERR

# Configuración Global
export LC_ALL=C
ISO_NAME="ArchDroid-AI"
ISO_VERSION=$(date +%Y.%m.%d)
WORK_DIR="/opt/archdroid-iso"
BUILD_USER="archdroid-builder"

# Colores y Logging
BOLD=$(tput bold)
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
RESET=$(tput sgr0)

handle_error() {
    local line=$1
    echo "${RED}${BOLD}ERROR: Fallo en línea $line${RESET}" >&2
    exit 1
}

check_dependencies() {
    local deps=("archiso" "git" "reflector" "squashfs-tools" "qemu")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            echo "${RED}Falta dependencia: $dep${RESET}"
            exit 1
        fi
    done
}

setup_environment() {
    echo "${GREEN}${BOLD}[+] Configurando entorno...${RESET}"
    useradd -m -s /bin/bash "$BUILD_USER" || true
    mkdir -p "$WORK_DIR"
    chown -R "$BUILD_USER":"$BUILD_USER" "$WORK_DIR"
    
    # Optimizar mirrors
    reflector --protocol https --latest 10 --sort rate --save /etc/pacman.d/mirrorlist
}

build_iso() {
    su - "$BUILD_USER" << EOF
    cd "$WORK_DIR"
    cp -r /usr/share/archiso/configs/releng ./build
    cd build

    # Personalizar lista de paquetes
    echo -e "linux-zen\nlinux-zen-headers\nnvidia-dkms\nwaydroid\ndeepseek-coder\ngnome\nvirt-manager\nyay" > packages.x86_64

    # Configuración del kernel
    cat << 'EOL' > airootfs/etc/mkinitcpio.conf
MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm amdgpu)
BINARIES=(/usr/bin/btrfs)
HOOKS=(base systemd autodetect modconf block filesystems keyboard fsck grub-btrfs-overlayfs)
EOL

    # Script de instalación automática
    curl -sL https://raw.githubusercontent.com/archdroid-ai/installer/main/archdroid-installer.sh -o airootfs/usr/local/bin/archdroid-install
    chmod +x airootfs/usr/local/bin/archdroid-install

    # Configuración de seguridad
    echo "archdroid ALL=(ALL) NOPASSWD: ALL" > airootfs/etc/sudoers.d/10-archdroid
    chmod 440 airootfs/etc/sudoers.d/10-archdroid

    # Construir ISO
    mkarchiso -v \
        -w "$WORK_DIR/tmp" \
        -D "ArchDroid Installer" \
        -A "ArchDroid-AI x86_64" \
        -p "base-devel git reflector" \
        -L "$ISO_NAME" \
        -o "$WORK_DIR/output" .
EOF
}

post_process() {
    echo "${GREEN}${BOLD}[+] Post-procesando ISO...${RESET}"
    local output_iso="$WORK_DIR/output/$ISO_NAME-$ISO_VERSION-x86_64.iso"
    
    # Firmar ISO
    gpg --detach-sign --armor "$output_iso"
    
    # Generar checksums
    sha256sum "$output_iso" > "$output_iso.sha256"
    b3sum "$output_iso" > "$output_iso.b3"

    # Comprimir con zstd
    zstd --ultra -22 --threads=0 "$output_iso"
}

main() {
    check_dependencies
    setup_environment
    build_iso
    post_process
    
    echo "${GREEN}${BOLD}[+] ISO generada en: $WORK_DIR/output/${RESET}"
    ls -lh "$WORK_DIR/output"
}

main
