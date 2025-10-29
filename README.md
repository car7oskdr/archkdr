    # 🧰 Arch Linux DevOps Installer (Hyprland + GNOME + AWS Ready)

    Instalador automatizado de **Arch Linux** diseñado para entornos **DevOps / Platform Engineering**.  
    Configura un sistema completo con herramientas modernas para desarrollo, virtualización, automatización y AWS, todo listo en una sola ejecución.

    ---

    ## ⚠️ Advertencia

    > 🚨 Este script **borra completamente el disco `/dev/nvme0n1`** y realiza una instalación limpia de Arch Linux.  
    > No lo ejecutes en un sistema con datos importantes.

    ---

    ## 🧩 Características principales

    | Categoría | Descripción |
    |------------|--------------|
    | 🖥️ **Base del sistema** | Arch Linux (UEFI, GPT, Btrfs, kernel `linux-zen`) |
    | 🔒 **Particionado** | EFI (512 MiB) + Btrfs (subvolúmenes @, @home, @log, @pkg, @tmp, @swap) + Swapfile 8 GB |
    | ⚙️ **Gestor de arranque** | `systemd-boot` |
    | 🧠 **Sistema de archivos** | `btrfs` con compresión zstd y subvolúmenes optimizados |
    | 🌎 **Locales** | `es_MX.UTF-8`, `en_US.UTF-8` |
    | 🕓 **Zona horaria** | America/Mexico_City |
    | 🔐 **Usuarios** | Crea usuario administrador y deshabilita `root` (sudo con grupo `wheel`) |
    | 🧱 **Shell** | `zsh` + `oh-my-zsh` + plugins (`git`, `zsh-autosuggestions`, `zsh-syntax-highlighting`) |
    | 💻 **Entorno gráfico** | GNOME + Hyprland (Wayland) |
    | 🧰 **Terminal** | `kitty` con ligaduras, transparencia y atajos personalizados |
    | ✨ **Editor** | `Neovim` + `LazyVim` + `Codeium` (AI autocompletado) |
    | 🐳 **Contenedores** | Docker + Compose v2 + soporte `buildx` |
    | 🌐 **Red / VPN** | NetworkManager + nm-connection-editor + WireGuard + OpenVPN |
    | 🔥 **Firewall** | `ufw` (deny in / allow out, SSH abierto) |
    | 💬 **AUR Helper** | `paru` |
    | 🪶 **Fuentes** | JetBrains Mono, Fira Code, Nerd Fonts Symbols |
    | 💡 **Extras DevOps / AWS** | AWS CLI v2, Pulumi, AWS SAM, jq/yq, docker-buildx, aws-vault |
    | 🧰 **Utilidades** | fastfetch, htop, git, curl, bluez, pipewire |

    ---

    ## 🏗️ Estructura general

    El script realiza las siguientes etapas:

    1. **Recolección de datos del usuario** (hostname, usuario, contraseñas).  
    2. **Formateo completo del disco** `/dev/nvme0n1` y creación de particiones EFI + Btrfs.  
    3. **Creación de subvolúmenes Btrfs** y swapfile de 8 GB.  
    4. **Instalación del sistema base** con `pacstrap`.  
    5. **Configuración regional**, locales y zona horaria.  
    6. **Creación de usuario administrador**, `sudo`, bloqueo de root.  
    7. **Instalación del entorno gráfico** GNOME + Hyprland.  
    8. **Configuración de terminal, shell, firewall y Docker.**  
    9. **Instalación de herramientas DevOps/AWS.**  
    10. **Configuración estética** (kitty.conf, hyprland.conf, waybar, wofi).  
    11. **Creación de sesión autostart GNOME** para layouts `es` / `us`.  
    12. **Opción Rootless Docker** (con variable `ROOTLESS_DOCKER=1`).  
    13. **Desmontaje y fin de instalación.**

    ---

    ## 🧾 Requisitos previos

    - Arrancar desde el **ISO oficial de Arch Linux** (UEFI mode).
    - Conexión a Internet activa (Ethernet o Wi-Fi mediante `iwctl`).
    - Disco `/dev/nvme0n1` disponible (todo será eliminado).
    - Ejecución como `root` o usuario live con permisos totales.

    ---

    ## 🚀 Instalación

    ### 1️⃣ Descargar el script
    Desde el entorno Live de Arch:

    ```bash
    curl -O https://raw.githubusercontent.com/<tu_usuario>/<tu_repo>/main/arch_autoinstall_v2.sh
    chmod +x arch_autoinstall_v2.sh
