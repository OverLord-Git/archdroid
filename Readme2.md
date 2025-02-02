Guía de Uso Avanzado 🚀
Preparar Medios de Instalación

bash
Copy
# Desde sistema Arch Linux existente
sudo pacman -S git
git clone https://github.com/archdroid-ai/installer
cd installer
Configurar Variables (opcional)

bash
Copy
cp archdroid.conf.example archdroid.conf
nano archdroid.conf  # Editar parámetros
Ejecutar en Modo Automático

bash
Copy
sudo ./installer.sh --config archdroid.conf
Opciones Avanzadas

bash
Copy
# Forzar modo legacy BIOS
sudo ./installer.sh --bios

# Deshabilitar Secure Boot
sudo ./installer.sh --no-secureboot

# Instalar sin interfaz gráfica
sudo ./installer.sh --cli

# Modo depuración
sudo ./installer.sh --debug
Flujo de Instalación ⚙️
Verificación de Requisitos

Hardware compatible

Conexión a Internet estable

Espacio en disco suficiente

Configuración de Disco

Cifrado automático con TPM2

Creación de particiones optimizadas

Formateo con Btrfs/Zstd

Instalación del Sistema Base

Kernel Zen con parches de rendimiento

Controladores de hardware esenciales

Herramientas de desarrollo

Optimizaciones Post-Instalación

Configuración de GPU específica

Servicios de IA auto-activados

Perfiles de energía personalizados

Configuración Final

Instalación de GNOME con extensiones

Habilitación de servicios esenciales

Protección Secure Boot

Recomendaciones de Hardware 💻
Componente	Mínimo Recomendado
CPU	Intel 8th Gen / Ryzen 3000+
GPU	NVIDIA GTX 10xx / AMD RX 500
RAM	8GB DDR4 (16GB recomendado)
Almacen.	NVMe PCIe 3.0 256GB+
Red	Wi-Fi 6 / 2.5Gb Ethernet
Este instalador representa la evolución de la instalación automática de sistemas Linux, combinando seguridad empresarial con rendimiento gaming y herramientas de IA de última generación. ¿Necesitas más personalizaciones específicas?
