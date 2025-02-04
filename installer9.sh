#!/usr/bin/env bash
# ARCHDROID DESKTOP EDITION v9.0 (DeepSeek AI Integrated)
set -euo pipefail
trap 'cleanup && exit 1' ERR

# Configuración Global
declare -A CFG=(
    [USER]="archuser"
    [PASS]="$(openssl rand -base64 12)"
    [HOST]="deepseek-desktop"
    [DISK]="/dev/nvme0n1"
    [TZ]="America/New_York"
    [KERNEL]="linux-zen"
    [FS]="btrfs"
    [DE]="gnome"
    [GPU]="auto"
    [AI_MODEL]="deepseek-7b-Q8_0"
)

# Repositorios y Paquetes
REPOS=("community" "extra" "multilib")
CORE_PKGS=(
    base base-devel linux-zen linux-zen-headers grub efibootmgr networkmanager 
    git zsh reflector flatpak appimagelauncher nvidia-dkms vulkan-icd-loader 
    lib32-nvidia-utils python-pip python-venv python-numpy llama-cpp-python
)

DEEPSEEK_MODELS=(
    "https://huggingface.co/TheBloke/deepseek-7B-GGUF/resolve/main/deepseek-7b.Q8_0.gguf"
    "https://huggingface.co/TheBloke/deepseek-math-7B-GGUF/resolve/main/deepseek-math-7b.Q8_0.gguf"
)

setup_ai() {
    echo "🧠 Configurando DeepSeek AI..."
    local ai_dir="/opt/deepseek"
    
    # Crear entorno Python
    sudo -u "${CFG[USER]}" python -m venv "${ai_dir}/venv"
    source "${ai_dir}/venv/bin/activate"
    
    # Instalar dependencias
    pip install --upgrade pip
    pip install fastapi uvicorn sse-starlette python-multipart
    
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

install_ai_deps() {
    case "${CFG[GPU]}" in
        "nvidia")
            echo "📦 Instalando soporte CUDA..."
            sudo pacman -S --noconfirm cuda cudnn python-nvidia-cuda
            ;;
        "amd")
            echo "📦 Instalando soporte ROCm..."
            sudo pacman -S --noconfirm rocm-hip-sdk rocblas hipblas
            ;;
    esac
    
    # Recompilar llama-cpp-python con soporte GPU
    sudo -u "${CFG[USER]}" pip install --force-reinstall --no-cache-dir llama-cpp-python
}

configure_user() {
    arch-chroot /mnt /bin/bash <<EOF
    echo 'alias deepseek="curl -X POST http://localhost:8000/generate -d '\''{\"prompt\": \"\"}'\"' >> /home/${CFG[USER]}/.zshrc
    echo 'export PATH=\$PATH:/opt/deepseek/venv/bin' >> /home/${CFG[USER]}/.zshrc
EOF
}

main() {
    [[ -d /sys/firmware/efi ]] || { echo "❌ Sistema no UEFI"; exit 1; }
    
    setup_repos
    detect_gpu
    setup_disk
    install_system
    install_ai_deps
    setup_ai
    configure_desktop
    configure_user
    
    echo "✅ Instalación completada!"
    echo "   Accede a la API: http://localhost:8000/docs"
    echo "   Ejemplo de uso: deepseek 'Explique la teoría de la relatividad'"
    echo "   Reinicia con: reboot"
}

# ... (mantener funciones anteriores de partitioning, disk setup, etc)
