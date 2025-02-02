Guía de Instalación Completa
1. Preparación del Medio de Instalación:

Descargar Arch Linux ISO

Grabar ISO en USB con Rufus/balenaEtcher (modo DD)

Arrancar desde el USB

2. Conexión a Internet:

bash
Copy
iwctl # Para Wi-Fi
station wlan0 connect "SSID"
dhcpcd # Para cable
ping archlinux.org # Verificar conexión
3. Ejecución del Instalador:

bash
Copy
curl -O https://raw.githubusercontent.com/usuario/archdroid-ai/main/installer.sh
chmod +x installer.sh
./installer.sh
4. Proceso Automático:

El script realizará:

Particionado automático con cifrado LUKS

Instalación del sistema base

Configuración de usuarios (archdroid/1)

Instalación de drivers según GPU detectada

Configuración de GNOME

Optimizaciones de rendimiento

Reinicio automático al finalizar

5. Primer Inicio:

Usuario: archdroid

Contraseña: 1

Root Password: 1

Acceso sudo sin contraseña

6. Características Clave:

Cifrado completo del disco

Kernel Zen con optimizaciones

Rendimiento máximo en CPU/GPU

Entorno GNOME preconfigurado

Actualizaciones automáticas habilitadas

Firewall básico configurado

7. Comandos Post-Instalación Útiles:

bash
Copy
# Actualizar sistema
sudo pacman -Syu

# Administrar servicios
sudo systemctl start|stop|status servicio

# Monitor de rendimiento
sudo htop

# Configurar Waydroid (opcional)
sudo pacman -S waydroid && waydroid init
8. Seguridad Recomendada:

bash
Copy
# Cambiar contraseña después de instalar
passwd

# Configurar autenticación SSH por clave
ssh-keygen -t ed25519
Notas Importantes:

Todo el disco será formateado automáticamente

El sistema usa 100% de espacio disponible

Configuración orientada a máximo rendimiento

Incluye soporte completo para Virtualización

Este sistema está listo para producción con todas las optimizaciones necesarias y configuración profesional automatizada. ¡Disfruta de ArchDroid-AI!
