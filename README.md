Arch Linux Laptop Installer (Base + Post-Install)

Instalador modular y reproducible de Arch Linux para laptops modernas, con separación estricta entre:

Instalación base del sistema (boot, disco, kernel, GNOME).

Post-instalación de herramientas (DevOps, AUR, Python con uv, Pulumi).

Este enfoque sigue la filosofía de Arch Linux: sistema mínimo, control total y tooling desacoplado.

🎯 Objetivos del proyecto

Instalación limpia y repetible de Arch Linux

Kernel linux-zen para mejor latencia y experiencia interactiva

Btrfs con subvolúmenes (preparado para snapshots)

UEFI + systemd-boot

GNOME + GDM (Wayland)

Soporte para laptop Intel + NVIDIA híbrida

Separación clara entre:

sistema base

herramientas de usuario / DevOps

Uso de uv como gestor moderno de Python (no pip)

Infra como código con Pulumi

🗂️ Estructura del repositorio
arch-install/
├── 01_install_arch_base.sh      # Instalación base del sistema (root)
├── 02_post_install_tools.sh     # Tooling post-instalación (usuario)
└── README.md

⚠️ Advertencias importantes

❗ El script de instalación base borra COMPLETAMENTE el disco

❗ Diseñado para sistemas UEFI

❗ Disco por defecto: /dev/nvme0n1

❗ Sin cifrado LUKS (por ahora)

❗ Ejecutar solo desde el Arch ISO oficial

Si necesitas LUKS, BIOS legacy, o discos distintos, el script debe ajustarse.

🧱 Script 01 — Instalación base de Arch

Archivo: 01_install_arch_base.sh
Dónde se ejecuta: archiso (root)
Qué hace:

Sistema

Arch Linux limpio

Kernel linux-zen

Firmware + SOF (audio Intel)

Locales: en_US.UTF-8, es_MX.UTF-8

Zona horaria: America/Mexico_City

Disco

GPT

Particiones:

EFI (512 MB)

ROOT (Btrfs)

Subvolúmenes Btrfs:

@

@home

@log

@pkg

Compresión zstd

Boot

systemd-boot

Microcode Intel

Entrada de arranque dedicada a linux-zen

Desktop

GNOME + GDM

Wayland por defecto

Laptop / Hardware

Intel audio (SOF)

NVIDIA híbrida (nvidia-prime)

NetworkManager

PipeWire

Usuario

Usuario normal

sudo habilitado para grupo wheel

Shell por defecto: zsh

👉 No instala tooling DevOps ni AUR helpers.

Uso
chmod +x 01_install_arch_base.sh
./01_install_arch_base.sh


Cuando termine:

reboot

🧰 Script 02 — Post-instalación de herramientas

Archivo: 02_post_install_tools.sh
Dónde se ejecuta: ya dentro del sistema, como usuario normal
Usa: sudo internamente

Qué instala
Base

paru (AUR helper)

base-devel

utilidades comunes (curl, git, etc.)

Contenedores

Docker

Docker Compose

Docker Buildx

Usuario agregado al grupo docker

Python moderno

python (solo runtime)

❌ No se usa pip como workflow

✅ uv como gestor de paquetes y entornos

~/.local/bin agregado correctamente al PATH (.zshrc + .zprofile)

Infra / DevOps

Pulumi (pulumi-bin desde AUR)

Utilidades

jq, yq

neovim

openssh

herramientas de CLI comunes

❌ No instala GCP ni Azure
❌ No instala IDEs ni tooling extra innecesario

Uso
chmod +x 02_post_install_tools.sh
./02_post_install_tools.sh


Después:

Cierra sesión y vuelve a entrar (grupo docker)

O abre una nueva terminal para cargar el PATH

✅ Verificaciones recomendadas
uname -r
# debe mostrar: *zen*

uv --version
pulumi version

docker run hello-world

🧠 Filosofía del diseño

Instalador base ≠ entorno de trabajo

El sistema debe:

arrancar

ser estable

ser mínimo

El tooling:

es intercambiable

se puede reinstalar

no debe romper el sistema base

Este diseño permite:

reinstalar Arch en minutos

reutilizar tooling

versionar cambios con control

🔜 Posibles extensiones futuras

(no incluidas por ahora)

LUKS

Snapshots Btrfs (Snapper / Timeshift)

Perfil batería vs performance

Hyprland opcional

Hardening ligero

Bootstrap por tipo de proyecto (infra / CLI / backend)

🧾 Estado actual

✔ Estable
✔ Reproducible
✔ Modular
✔ Alineado con Arch Linux
✔ Apto para laptop DevOps
