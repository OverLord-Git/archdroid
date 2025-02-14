#!/bin/bash
# --------------------------------------------
# HybridOS AI Subsystem Installer
# --------------------------------------------

LOG_FILE="/var/log/hybridos_ai.log"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOG_FILE
}

install_ai() {
  log "Instalando componentes de IA..."
  yay -S --noconfirm ollama python-pip \
    tensorflow onnxruntime

  log "Descargando modelo Mistral-7B..."
  ollama pull mistral:7b-instruct-q4_K_M

  log "Integrando con GNOME..."
  git clone https://github.com/hybridos/gnome-ai-assistant.git
  cd gnome-ai-assistant && sudo make install
}

main() {
  install_ai
  log "Sistema de IA listo! Hotkey: Super+Ctrl+A"
}

main "$@"
