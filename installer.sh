#!/usr/bin/env bash
# ARCHDROID UNIVERSAL INSTALLER v10.0
set -euo pipefail
trap 'cleanup && exit 1' ERR

# Configuración Global
declare -A CFG=(
    [USER]="archuser"
    [PASS]="$(openssl rand -base64 12)"
    [HOST]="archdroid"
    [DISK]="/dev/nvme0n1"
    [TZ]="America/New_York"
    [KERNEL]="linux-zen"
    [FS]="btrfs"
    [MODE]="desktop"  # desktop/mobile/server
    [DE]="gnome"      # gnome/kde/phosh
    [GPU]="auto"
    [AI_MODEL]="deepseek-7b-Q8_0"
)

# Repositorios y Paquetes
REPOS=("community" "extra" "multilib" "cachyos")
CORE_PKGS=(
    base base-devel linux-zen linux-zen-headers grub efibootmgr networkmanager 
    git zsh reflector flatpak appimagelauncher python-pip python-venv
    nvidia-dkms vulkan-icd-loader lib32-nvidia-utils steam wine-staging
)

DEEPSEEK_MODELS=(
    "https://huggingface.co/TheBloke/deepseek-7B-GGUF/resolve/main/deepseek-7b.Q8_0.gguf"
    "https://huggingface.co/TheBloke/deepseek-math-7B-GGUF/resolve/main/deepseek-math-7b.Q8_0.gguf"
)

# Funciones Principales
setup_repos() {
    echo "🔄 Configurando repositorios..."
    for repo in "${REPOS[@]}"; do
        sudo sed -i "/^#\[$repo\]/s/^#//" /etc/pacman.conf
    done
    sudo pacman-key --recv-keys F3B607488DB35A47 --keyserver keyserver.ubuntu.com
    sudo pacman-key --lsign-key F3B607488DB35A47
    sudo pacman -Sy
}

detect_gpu() {
    if lspci | grep -qi "nvidia"; then
        CFG[GPU]="nvidia"
        export CMAKE_ARGS="-DLLAMA_CUBLAS=on"
    elif lspci | grep -qi "amd"; then
        CFG[GPU]="amd"
        export CMAKE_ARGS="-DLLAMA_HIPBLAS=on"
    else
        CFG[GPU]="cpu"
    fi
    echo "✅ Aceleración AI: ${CFG[GPU]}"
}

setup_ai() {
    echo "🧠 Configurando DeepSeek AI..."
    local ai_dir="/opt/deepseek"
    
    # Crear entorno Python
    sudo -u "${CFG[USER]}" python -m venv "${ai_dir}/venv"
    source "${ai_dir}/venv/bin/activate"
    
    # Instalar dependencias
    pip install --upgrade pip
    pip install fastapi uvicorn sse-starlette llama-cpp-python
    
    # Descargar modelos
    sudo mkdir -p "${ai_dir}/models"
    for model in "${DEEPSEEK_MODELS[@]}"; do
        sudo -u "${CFG[USER]}" wget -q --show-progress -P "${ai_dir}/models" "$model"
    done

    # Crear servicio API
    sudo tee /etc/systemd/system/deepseek-api.service >/dev/null <<EOF
[Unit]
Description=DeepSeek AI API Service
After=network.target

[Service]
User=${CFG[USER]}
WorkingDirectory=${ai_dir}
ExecStart=${ai_dir}/venv/bin/uvicorn main:app --host 0.0.0.0 --port 8000
Environment="MODEL_PATH=${ai_dir}/models/${CFG[AI_MODEL]}.gguf"
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    # Crear aplicación FastAPI
    sudo tee "${ai_dir}/main.py" >/dev/null <<'EOF'
from fastapi import FastAPI
from fastapi.responses import StreamingResponse
from llama_cpp import Llama
import os

app = FastAPI()
llm = Llama(
    model_path=os.environ["MODEL_PATH"],
    n_ctx=4096,
    n_gpu_layers=-1,
    n_threads=8
)

@app.post("/generate")
async def generate(prompt: str, max_tokens: int = 200):
    stream = llm.create_chat_completion(
        messages=[{"role": "user", "content": prompt}],
        max_tokens=max_tokens,
        stream=True
    )
    
    def event_stream():
        for chunk in stream:
            yield f"data: {chunk['choices'][0]['delta'].get('content', '')}\n\n"

    return StreamingResponse(event_stream(), media_type="text/event-stream")
EOF

    # Permisos y activación
    sudo chown -R "${CFG[USER]}":"${CFG[USER]}" "${ai_dir}"
    sudo systemctl enable deepseek-api.service
}

setup_disk() {
    echo "💾 Particionando disco..."
    parted -s "${CFG[DISK]}" mklabel gpt
    parted -s "${CFG[DISK]}" mkpart ESP fat32 1MiB 513MiB set 1 esp on
    parted -s "${CFG[DISK]}" mkpart primary 513MiB 100%
    
    mkfs.fat -F32 "${CFG[DISK]}p1"
    cryptsetup luksFormat --type luks2 "${CFG[DISK]}p2" <<< "${CFG[PASS]}"
    cryptsetup open "${CFG[DISK]}p2" cryptroot <<< "${CFG[PASS]}"
    
    mkfs.btrfs -L ROOT /dev/mapper/cryptroot
    mount /dev/mapper/cryptroot /mnt
    mkdir -p /mnt/boot && mount "${CFG[DISK]}p1" /mnt/boot
}

install_system() {
    echo "🚀 Instalando sistema base..."
    pacstrap /mnt "${CORE_PKGS[@]}"
    genfstab -U /mnt >> /mnt/etc/fstab
}

configure_system() {
    arch-chroot /mnt /bin/bash <<EOF
    ln -sf "/usr/share/zoneinfo/${CFG[TZ]}" /etc/localtime
    hwclock --systohc
    echo "LANG=en_US.UTF-8" > /etc/locale.conf
    echo "KEYMAP=us" > /etc/vconsole.conf
    echo "${CFG[HOST]}" > /etc/hostname
    
    useradd -m -G wheel,audio,video,storage -s /bin/zsh "${CFG[USER]}"
    echo "${CFG[USER]}:${CFG[PASS]}" | chpasswd
    echo "root:${CFG[PASS]}" | chpasswd
    echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/10-archdroid
    
    systemctl enable NetworkManager fstrim.timer systemd-oomd
EOF
}

cleanup() {
    umount -R /mnt 2>/dev/null || true
    cryptsetup close cryptroot 2>/dev/null || true
}

main() {
    [[ -d /sys/firmware/efi ]] || { echo "❌ Sistema no UEFI"; exit 1; }
    
    setup_repos
    detect_gpu
    setup_disk
    install_system
    configure_system
    setup_ai
    
    echo "✅ Instalación completada!"
    echo "   Usuario: ${CFG[USER]}"
    echo "   Password: ${CFG[PASS]}"
    echo "   Accede a la API: http://localhost:8000/docs"
    echo "   Reinicia con: reboot"
}

main
