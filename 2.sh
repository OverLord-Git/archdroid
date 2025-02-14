#!/bin/bash
# --------------------------------------------
# HybridOS Android & Tools Installer
# --------------------------------------------

# Configuración
LOG_FILE="/var/log/hybridos_android.log"
export LC_ALL=en_US.UTF-8

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOG_FILE
}

install_stack() {
  log "Instalando herramientas esenciales..."
  sudo pacman -S --noconfirm \
    yay flatpak wine-staging winetricks \
    steam proton-ge-custom-bin docker \
    lxc lxd waydroid

  log "Configurando Docker..."
  sudo systemctl enable docker
  sudo usermod -aG docker $USER

  log "Iniciando Waydroid..."
  sudo systemctl start lxd
  waydroid init
}

main() {
  install_stack
  log "Capa Android instalada! Ejecute ai_subsystem.sh"
}

main "$@"
