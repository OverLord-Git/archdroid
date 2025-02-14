#!/bin/bash
# --------------------------------------------
# HybridOS Android & Tools Installer
# Autor: Chief Architect OS
# --------------------------------------------

# ===== INSTALACIÓN DE HERRAMIENTAS =====
install_tools() {
  log "Instalando herramientas esenciales..."
  sudo pacman -S --noconfirm \
    yay flatpak unzip unrar p7zip \
    wine-staging winetricks protontricks \
    steam docker

  sudo systemctl enable docker
  sudo usermod -aG docker $USER

  flatpak install -y \
    com.discordapp.Discord \
    com.spotify.Client \
    org.blender.Blender
}

# ===== CONFIGURAR ENTORNO DE GAMING =====
setup_gaming() {
  log "Configurando Steam y Proton..."
  yay -S --noconfirm proton-ge-custom-bin
  mkdir -p ~/.steam/root/compatibilitytools.d
  cp -r /usr/share/steam/compatibilitytools.d/* ~/.steam/root/compatibilitytools.d/
}

main() {
  install_tools
  setup_gaming
  log "Herramientas y gaming configurados!"
}
