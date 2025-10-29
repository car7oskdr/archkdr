#!/usr/bin/env bash
# arch_autoinstall_v2.sh
# ATENCIÓN: FORMATEA COMPLETAMENTE /dev/nvme0n1
# Perfil:
# - UEFI, GPT: EFI 512MiB + Btrfs sin LUKS (subvols + swapfile 8G)
# - Kernel linux-zen + microcode CPU
# - systemd-boot
# - GNOME + GDM + Hyprland (Wayland) + Waybar + hyprpaper + wofi + portals
# - NetworkManager, nm-connection-editor, OpenVPN, WireGuard
# - Kitty + Zsh + Oh-My-Zsh (+ autosuggestions + syntax-highlighting)
# - Neovim + LazyVim + Codeium
# - Docker (rootful por defecto; rootless si ROOTLESS_DOCKER=1)
# - Paru (AUR)
# - UFW (deny in / allow out)
# - Locales: es_MX.UTF-8 / en_US.UTF-8 ; Keymap consola: la-latin1
# - Zona horaria: America/Mexico_City
#
# Uso (rootless opcional):
#   ROOTLESS_DOCKER=1 bash arch_autoinstall_v2.sh
#   (o sin flag para modo Docker rootful clásico)

set -euo pipefail

### ====== 0) Confirmación letal ======
echo "⚠️  Este script BORRARÁ COMPLETAMENTE /dev/nvme0n1."
read -rp "Escribe 'INSTALAR' para continuar: " ACK
[[ "${ACK:-}" == "INSTALAR" ]] || { echo "Abortado."; exit 1; }

### ====== 1) Entradas del usuario ======
read -rp "Hostname: " HOSTNAME
read -rp "Usuario administrador: " USERNAME
read -rsp "Contraseña para ${USERNAME}: " USERPASS; echo
read -rsp "Repite la contraseña: " USERPASS2; echo
[[ "$USERPASS" == "$USERPASS2" ]] || { echo "Contraseñas no coinciden."; exit 1; }

DISK="/dev/nvme0n1"
EFI_SIZE="512MiB"
SWAP_SIZE_GB=8
ROOTLESS_DOCKER="${ROOTLESS_DOCKER:-0}"   # 1=habilita rootless; 0=modo clásico

### ====== 2) Pre-chequeos ======
lsblk "$DISK" >/dev/null || { echo "No existe $DISK"; exit 1; }
ping -c1 archlinux.org >/dev/null 2>&1 || echo "Aviso: sin ping; asumo pacman OK."

### ====== 3) Particionado (GPT: EFI + Btrfs) ======
echo ">> Particionando $DISK"
sgdisk --zap-all "$DISK"
parted -s "$DISK" mklabel gpt \
  mkpart ESP fat32 1MiB "$EFI_SIZE" \
  set 1 esp on \
  mkpart btrfs "$EFI_SIZE" 100%

EFI_PART="${DISK}p1"
ROOT_PART="${DISK}p2"
sleep 1

mkfs.fat -F32 "$EFI_PART"
mkfs.btrfs -f "$ROOT_PART"

### ====== 4) Subvolúmenes Btrfs ======
mount "$ROOT_PART" /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@log
btrfs subvolume create /mnt/@pkg
btrfs subvolume create /mnt/@tmp
btrfs subvolume create /mnt/@swap
umount /mnt

BTRFS_OPTS="noatime,ssd,compress=zstd:3,space_cache=v2"
mount -o "${BTRFS_OPTS},subvol=@"   "$ROOT_PART" /mnt
mkdir -p /mnt/{boot,home,var/log,var/cache/pacman/pkg,tmp,swap}
mount -o "${BTRFS_OPTS},subvol=@home" "$ROOT_PART" /mnt/home
mount -o "${BTRFS_OPTS},subvol=@log"  "$ROOT_PART" /mnt/var/log
mount -o "${BTRFS_OPTS},subvol=@pkg"  "$ROOT_PART" /mnt/var/cache/pacman/pkg
mount -o "noatime,ssd,nodatacow"     "$ROOT_PART" /mnt/swap
chmod 700 /mnt/swap
mount "$EFI_PART" /mnt/boot

### ====== 5) Swapfile Btrfs ======
echo ">> Creando swapfile ${SWAP_SIZE_GB}G"
chattr +C /mnt/swap
btrfs property set /mnt/swap compression none || true
fallocate -l "${SWAP_SIZE_GB}G" /mnt/swap/swapfile
chmod 600 /mnt/swap/swapfile
mkswap /mnt/swap/swapfile

### ====== 6) Mirrors y pacstrap ======
reflector --country Mexico,United\ States --latest 10 --sort rate --save /etc/pacman.d/mirrorlist 2>/dev/null || true
pacman -Sy --noconfirm || true

KERNEL_PKGS=(linux-zen linux-zen-headers)
BASE_PKGS=(base base-devel linux-firmware btrfs-progs networkmanager sudo zsh git curl wget openssh \
           reflector man-db man-pages texinfo efibootmgr dosfstools mtools \
           xdg-user-dirs xdg-utils pipewire wireplumber pipewire-alsa pipewire-pulse \
           gnome-keyring)
# microcode según CPU
if lscpu | grep -qi intel; then UCODE=intel-ucode; else UCODE=amd-ucode; fi

# Intel + Wayland
GFX_PKGS=(mesa vulkan-intel intel-media-driver libva-intel-driver)

# GNOME + GDM
GNOME_PKGS=(gnome gdm gnome-tweaks gnome-backgrounds)

# Hyprland stack
HYPR_PKGS=(hyprland waybar hyprpaper wofi grim slurp wl-clipboard \
           xdg-desktop-portal xdg-desktop-portal-gtk xdg-desktop-portal-hyprland)

# Red y VPN
NET_PKGS=(nm-connection-editor networkmanager-openvpn wireguard-tools openvpn)

# Terminal + dev
DEV_PKGS=(kitty neovim unzip tar ripgrep fd nodejs npm python-pipx cmake make pkgconf)

# Seguridad y extras
SEC_PKGS=(ufw bluez bluez-utils ttf-fira-code ttf-jetbrains-mono \
          ttf-nerd-fonts-symbols htop fastfetch)

# Docker
DOCKER_PKGS=(docker docker-compose docker-buildx)

pacstrap -K /mnt "${BASE_PKGS[@]}" "${KERNEL_PKGS[@]}" "$UCODE" \
              "${GFX_PKGS[@]}" "${GNOME_PKGS[@]}" "${HYPR_PKGS[@]}" \
              "${NET_PKGS[@]}" "${DEV_PKGS[@]}" "${SEC_PKGS[@]}" \
              "${DOCKER_PKGS[@]}"

genfstab -U /mnt >> /mnt/etc/fstab
echo "/swap/swapfile none swap defaults 0 0" >> /mnt/etc/fstab

### ====== 7) Config en chroot ======
arch-chroot /mnt /bin/bash -eux <<CHROOT
set -euo pipefail

HOSTNAME="$HOSTNAME"
USERNAME="$USERNAME"
SWAP_SIZE_GB="$SWAP_SIZE_GB"
ROOTLESS_DOCKER="$ROOTLESS_DOCKER"

# 7.1 Hostname / hosts
echo "\$HOSTNAME" > /etc/hostname
cat >/etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   \$HOSTNAME.localdomain \$HOSTNAME
EOF

# 7.2 Locales
sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
sed -i 's/^#es_MX.UTF-8/es_MX.UTF-8/' /etc/locale.gen
locale-gen
echo 'LANG=es_MX.UTF-8' > /etc/locale.conf

# 7.3 Keymap consola
echo 'KEYMAP=la-latin1' > /etc/vconsole.conf

# 7.4 Zona horaria y reloj
ln -sf /usr/share/zoneinfo/America/Mexico_City /etc/localtime
hwclock --systohc

# 7.5 Servicios base
systemctl enable NetworkManager
systemctl enable bluetooth
systemctl enable systemd-timesyncd

# 7.6 UFW
systemctl enable ufw
ufw default deny incoming || true
ufw default allow outgoing || true
ufw allow ssh || true
ufw --force enable || true

# 7.7 Usuario admin (root bloqueo)
useradd -m -G wheel,docker -s /bin/zsh "\$USERNAME"
passwd -l root
# sudoers
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# 7.8 systemd-boot
bootctl --path=/boot install
ROOT_UUID=\$(blkid -s UUID -o value \$(findmnt -no SOURCE /))
INITRD_UCODE=""
if pacman -Q intel-ucode >/dev/null 2>&1; then INITRD_UCODE="initrd  /intel-ucode.img"; fi
if pacman -Q amd-ucode   >/dev/null 2>&1; then INITRD_UCODE="initrd  /amd-ucode.img";   fi

cat >/boot/loader/loader.conf <<EOF
default arch
timeout 3
console-mode max
editor no
EOF

cat >/boot/loader/entries/arch.conf <<EOF
title   Arch Linux (linux-zen)
linux   /vmlinuz-linux-zen
\${INITRD_UCODE}
initrd  /initramfs-linux-zen.img
options root=UUID=\$ROOT_UUID rootflags=subvol=@ rw nowatchdog quiet splash
EOF

# 7.9 GDM/GNOME
systemctl enable gdm

# 7.10 Docker (modo rootful por defecto)
systemctl enable docker

# 7.11 XDG user dirs
sudo -u "\$USERNAME" xdg-user-dirs-update

# 7.12 Oh-My-Zsh + plugins
pacman -S --noconfirm zsh-autosuggestions zsh-syntax-highlighting
export RUNZSH=no CHSH=yes
sudo -u "\$USERNAME" sh -c 'curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh | bash'
ZSHRC="/home/\$USERNAME/.zshrc"
sed -i 's/^plugins=(git)$/plugins=(git zsh-autosuggestions zsh-syntax-highlighting)/' "\$ZSHRC" || true
sed -i 's/^ZSH_THEME=.*/ZSH_THEME="agnoster"/' "\$ZSHRC" || true

# 7.13 Paru (AUR)
pacman -S --noconfirm --needed base-devel
sudo -u "\$USERNAME" bash -lc '
  if ! command -v paru >/dev/null; then
    cd ~
    git clone https://aur.archlinux.org/paru.git
    cd paru
    makepkg -si --noconfirm
  fi
'

# 7.14 Neovim + LazyVim + Codeium
sudo -u "\$USERNAME" bash -lc '
  mkdir -p ~/.config
  if [ ! -d ~/.config/nvim ]; then
    git clone --depth=1 https://github.com/LazyVim/starter ~/.config/nvim
    cd ~/.config/nvim && rm -rf .git
  fi
  # Codeium plugin para LazyVim
  mkdir -p ~/.config/nvim/lua/plugins
  cat > ~/.config/nvim/lua/plugins/codeium.lua <<EOP
return {
  {
    "Exafunction/codeium.nvim",
    event = "InsertEnter",
    build = ":Codeium Auth",
    opts = {},
  },
}
EOP
'

# 7.15 Kitty config estética
sudo -u "\$USERNAME" bash -lc '
  mkdir -p ~/.config/kitty
  cat > ~/.config/kitty/kitty.conf <<EOK
font_family      JetBrains Mono
bold_font        auto
italic_font      auto
bold_italic_font auto
font_size        11.5
enable_ligatures always
cursor_shape     beam
cursor_blink     yes
background_opacity 0.95
confirm_os_window_close 0
scrollback_lines 5000
map ctrl+shift+enter new_window
map ctrl+shift+t     new_tab
map ctrl+shift+w     close_window
map ctrl+shift+h     previous_tab
map ctrl+shift+l     next_tab
EOK
'

# 7.16 Hyprland configuración (keybinds, layouts, wallpaper, portals)
sudo -u "\$USERNAME" bash -lc '
  mkdir -p ~/.config/hypr ~/.config/hypr/scripts ~/.config/hypr/wallpapers ~/.config/waybar ~/.config/wofi
  # Fondo: usar uno de GNOME backgrounds
  WALL="/usr/share/backgrounds/gnome/adwaita-day.jpg"
  [ -f "\$WALL" ] || WALL="/usr/share/backgrounds/adwaita-day.jpg"

  # hyprland.conf
  cat > ~/.config/hypr/hyprland.conf <<EHYPR
# --- Hyprland base ---
monitor=,preferred,auto,1
exec-once=hyprpaper &
exec-once=waybar &
exec-once=wofi --show drun &
env = XDG_CURRENT_DESKTOP,Hyprland
env = XDG_SESSION_TYPE,wayland
env = XDG_SESSION_DESKTOP,Hyprland
env = MOZ_ENABLE_WAYLAND,1
env = QT_QPA_PLATFORM,wayland
env = GTK_USE_PORTAL,1

input {
  kb_layout = es,us
  kb_options = grp:alt_shift_toggle
  repeat_delay = 250
  repeat_rate  = 40
  touchpad {
    natural_scroll = yes
    tap            = yes
  }
}

general {
  gaps_in = 6
  gaps_out = 12
  border_size = 2
  col.active_border = rgba(89b4faee) rgba(cba6f7ee) 45deg
  col.inactive_border = rgba(1e1e2eee)
  layout = dwindle
}

decoration {
  rounding = 8
  blur {
    enabled = yes
    size = 6
    passes = 2
  }
}

animations {
  enabled = yes
  bezier = ease, 0.05, 0.9, 0.1, 1.0
  animation = windows, 1, 7, ease
  animation = windowsOut, 1, 7, ease
  animation = border, 1, 10, ease
  animation = fade, 1, 7, ease
  animation = workspaces, 1, 6, ease
}

bind = SUPER, Return, exec, kitty
bind = SUPER, Q, killactive,
bind = SUPER, F, fullscreen,
bind = SUPER, Space, exec, wofi --show drun
bind = SUPER, E, exec, nautilus
bind = SUPER, L, exec, loginctl lock-session
bind = SUPER, V, togglefloating,
bind = SUPER, P, pseudo,
bind = SUPER, S, togglesplit,
bind = SUPER, H, movefocus, l
bind = SUPER, J, movefocus, d
bind = SUPER, K, movefocus, u
bind = SUPER, L, movefocus, r
bind = SUPER SHIFT, H, movewindow, l
bind = SUPER SHIFT, J, movewindow, d
bind = SUPER SHIFT, K, movewindow, u
bind = SUPER SHIFT, L, movewindow, r
bind = SUPER, 1, workspace, 1
bind = SUPER, 2, workspace, 2
bind = SUPER, 3, workspace, 3
bind = SUPER, 4, workspace, 4
bind = SUPER, mouse_down, workspace, e+1
bind = SUPER, mouse_up, workspace, e-1
EHYPR

  # hyprpaper (wallpaper)
  cat > ~/.config/hypr/hyprpaper.conf <<EHP
preload = \$WALL
wallpaper = ,\$WALL
EHP

  # Waybar (config simple)
  cat > ~/.config/waybar/config.jsonc <<EWB
{
  "layer": "top",
  "position": "top",
  "modules-left": ["hyprland/workspaces", "hyprland/window"],
  "modules-center": ["clock"],
  "modules-right": ["cpu", "memory", "network", "pulseaudio", "battery"],
  "clock": { "format": "{:%a %d %b %H:%M}" },
  "network": { "format-wifi": "{essid} ({signalStrength}%)", "format-ethernet": "eth {ifname}", "format-disconnected": "offline" },
  "pulseaudio": { "format": "{volume}% {icon}", "format-muted": "muted" }
}
EWB
  cat > ~/.config/waybar/style.css <<ECS
* { font-family: "JetBrains Mono", monospace; font-size: 12px; }
window { background: rgba(30,30,46,0.6); }
ECS

  # Wofi (tema básico)
  cat > ~/.config/wofi/style.css <<EWS
window { border: 2px solid #89b4fa; background-color: rgba(30,30,46,0.9); }
#input { margin: 6px; padding: 6px; }
EWS
'

# 7.17 Autostart primer login (GNOME): setear layouts ES/US + atajo Super+Space
sudo -u "\$USERNAME" bash -lc '
  mkdir -p ~/.config/autostart ~/.local/bin
  cat > ~/.local/bin/first-login-gnome.sh <<EOS
#!/usr/bin/env bash
set -e
# Aplicar layouts de teclado y atajo en GNOME
gsettings set org.gnome.desktop.input-sources sources "[('xkb', 'es'), ('xkb', 'us')]"
gsettings set org.gnome.desktop.input-sources xkb-options "['grp:win_space_toggle']"
# Deshabilitar autostart (se autoelimina)
rm -f ~/.config/autostart/first-login-gnome.desktop
EOS
  chmod +x ~/.local/bin/first-login-gnome.sh
  cat > ~/.config/autostart/first-login-gnome.desktop <<EOD
[Desktop Entry]
Type=Application
Exec=/home/\$USER/.local/bin/first-login-gnome.sh
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Name=First Login Setup (Keyboard ES/US)
Comment=Aplica ES/US y Super+Space en GNOME
EOD
'

# 7.18 Docker rootless opcional
if [ "\$ROOTLESS_DOCKER" = "1" ]; then
  pacman -S --noconfirm dbus-user-session uidmap slirp4netns fuse-overlayfs
  # Deshabilitar servicio rootful
  systemctl disable docker || true
  # Permitir servicios user al boot (loginctl linger)
  loginctl enable-linger "\$USERNAME" || true
  # Instalar rootless para el usuario
  sudo -u "\$USERNAME" bash -lc '
    export XDG_RUNTIME_DIR=/run/user/\$(id -u)
    export DBUS_SESSION_BUS_ADDRESS=unix:path=\$XDG_RUNTIME_DIR/bus
    dockerd-rootless-setuptool.sh install
    systemctl --user enable docker
  '
  echo ">> Docker rootless activado para \$USERNAME."
  echo "   Usa: export DOCKER_HOST=unix:///run/user/\$(id -u)/docker.sock"
fi

CHROOT

### ====== 8) Contraseña del usuario ======
echo ">> Configurando contraseña para ${USERNAME}"
arch-chroot /mnt /bin/bash -eux <<CHPASS
echo "${USERNAME}:${USERPASS}" | chpasswd
CHPASS

### ====== 9) Final ======
echo ">> Desmontando..."
swapoff /mnt/swap/swapfile || true
mount -o remount,ro /mnt || true
umount -R /mnt
echo "✅ Instalación lista. Reinicia (shutdown -r now)."
echo "Login: ${USERNAME}"
echo "- En GDM, elige GNOME o Hyprland."
echo "- GNOME aplicará layouts ES/US y Super+Space en el primer inicio."
echo "- Para Docker rootless: export DOCKER_HOST=unix:///run/user/\$(id -u)/docker.sock"
