#!/bin/bash
# --------------------------------------------
# HybridOS AI & Chatbot Installer
# Autor: Chief Architect OS
# --------------------------------------------

# ===== INSTALAR CHATBOT LOCAL =====
install_chatbot() {
  log "Instalando Chatbot Mistral-7B..."
  yay -S --noconfirm ollama python-pip
  pip install llama-cpp-python gnome-extensions-cli

  ollama pull mistral:7b-instruct-q4_K_M

  echo "[Unit]
Description=Chatbot Service
After=network.target

[Service]
ExecStart=/usr/bin/ollama serve
User=$USER

[Install]
WantedBy=default.target" | sudo tee /etc/systemd/system/chatbot.service

  sudo systemctl enable chatbot.service

  git clone https://github.com/hybridos/gnome-chatbot-extension.git
  cd gnome-chatbot-extension
  make install
}

# ===== CONFIGURAR API HYBRIDAI =====
setup_hybridai() {
  log "Configurando API HybridAI..."
  pip install fastapi uvicorn
  echo '{
    "ai_engine": "ollama",
    "model": "mistral:7b-instruct",
    "hotkey": "Ctrl+Alt+C"
  }' > ~/.config/hybridai.conf
}

main() {
  install_chatbot
  setup_hybridai
  log "Subsistema IA y Chatbot instalados! Use Ctrl+Alt+C para abrir."
}
