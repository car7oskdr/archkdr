#!/usr/bin/env bash
set -euo pipefail

echo "=== HYPRLAND INSTALL v2 (GNOME/GDM SAFE) ==="

# -------------------- Prechecks --------------------
if [[ "${EUID}" -eq 0 ]]; then
  echo "❌ No ejecutes esto como root. Úsalo como tu usuario normal."
  exit 1
fi

if ! command -v sudo >/dev/null 2>&1; then
  echo "❌ sudo no está disponible. Revisa tu instalación base."
  exit 1
fi

if ! command -v paru >/dev/null 2>&1; then
  echo "❌ paru no está instalado. Ejecuta primero 02_post_install_tools.sh"
  exit 1
fi

# Confirm sudo works early
sudo -v

# -------------------- Update --------------------
sudo pacman -Syu --noconfirm

# -------------------- Packages (official repos first) --------------------
sudo pacman -S --noconfirm --needed \
  hyprland \
  xdg-desktop-portal xdg-desktop-portal-gtk \
  waybar hyprpaper wofi \
  grim slurp wl-clipboard \
  polkit-gnome \
  pipewire wireplumber \
  brightnessctl playerctl \
  network-manager-applet \
  qt5-wayland qt6-wayland \
  noto-fonts noto-fonts-emoji ttf-jetbrains-mono ttf-fira-code \
  kitty pavucontrol \
  nautilus

# xdg-desktop-portal-hyprland may be in repos or AUR depending on timing
if pacman -Si xdg-desktop-portal-hyprland >/dev/null 2>&1; then
  sudo pacman -S --noconfirm --needed xdg-desktop-portal-hyprland
else
  paru -S --noconfirm --needed xdg-desktop-portal-hyprland
fi

# Optional Hypr extras: try repos, else AUR, ignore if missing
for pkg in hypridle hyprlock; do
  if pacman -Si "$pkg" >/dev/null 2>&1; then
    sudo pacman -S --noconfirm --needed "$pkg" || true
  else
    paru -S --noconfirm --needed "$pkg" || true
  fi
done

# Ensure GDM stays enabled (GNOME remains stable fallback)
sudo systemctl enable --now gdm

# -------------------- Environment (Wayland + NVIDIA hybrid safe defaults) --------------------
sudo install -d -m 0755 /etc/environment.d

# Use a unique heredoc delimiter and single quotes to prevent expansion
sudo tee /etc/environment.d/90-hyprland.conf >/dev/null <<'ENVEOF'
# Wayland hints (safe defaults)
XDG_SESSION_TYPE=wayland
NIXOS_OZONE_WL=1
MOZ_ENABLE_WAYLAND=1
QT_QPA_PLATFORM=wayland
QT_WAYLAND_DISABLE_WINDOWDECORATION=1
SDL_VIDEODRIVER=wayland

# NVIDIA/GBM (helps on hybrid setups; mostly harmless on Intel-only)
GBM_BACKEND=nvidia-drm
__GLX_VENDOR_LIBRARY_NAME=nvidia

# Some laptops/driver combos behave better with this on Wayland compositors
WLR_NO_HARDWARE_CURSORS=1
ENVEOF

# -------------------- Hyprland user config --------------------
HYPR_DIR="${HOME}/.config/hypr"
mkdir -p "${HYPR_DIR}"
mkdir -p "${HOME}/Pictures/Screenshots"

# Create a placeholder wallpaper if user doesn't have one
WALLPAPER="${HYPR_DIR}/wallpaper.jpg"
if [[ ! -f "${WALLPAPER}" ]]; then
  # Create a tiny placeholder (solid) wallpaper using ImageMagick if present; else skip.
  if command -v convert >/dev/null 2>&1; then
    convert -size 1920x1200 xc:"#1e1e2e" "${WALLPAPER}" || true
  fi
fi

cat > "${HYPR_DIR}/hyprland.conf" <<'HYPRCONF'
# =========================
# Hyprland minimal config (v2)
# GNOME remains installed as fallback via GDM session selector.
# =========================

monitor=,preferred,auto,1

$terminal = kitty
$menu = wofi --show drun

# ---------- Input ----------
input {
  kb_layout = latam,us
  kb_variant =
  kb_options = grp:alt_shift_toggle

  follow_mouse = 1

  touchpad {
    natural_scroll = yes
    tap-to-click = yes
  }
}

# ---------- Look & feel ----------
general {
  gaps_in = 5
  gaps_out = 12
  border_size = 2
  layout = dwindle
}

decoration {
  rounding = 10
  blur = yes
  blur_size = 8
  blur_passes = 3
  blur_new_optimizations = true
}

animations {
  enabled = yes
}

# ---------- Autostart ----------
exec-once = /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1
exec-once = nm-applet --indicator
exec-once = hyprpaper
exec-once = waybar

# ---------- Keybinds ----------
$mod = SUPER

bind = $mod, RETURN, exec, $terminal
bind = $mod, D, exec, $menu
bind = $mod, Q, killactive
bind = $mod, M, exit
bind = $mod, E, exec, nautilus
bind = $mod, V, togglefloating
bind = $mod, F, fullscreen, 1

# Focus
bind = $mod, H, movefocus, l
bind = $mod, L, movefocus, r
bind = $mod, K, movefocus, u
bind = $mod, J, movefocus, d

# Move windows
bind = $mod SHIFT, H, movewindow, l
bind = $mod SHIFT, L, movewindow, r
bind = $mod SHIFT, K, movewindow, u
bind = $mod SHIFT, J, movewindow, d

# Workspaces
bind = $mod, 1, workspace, 1
bind = $mod, 2, workspace, 2
bind = $mod, 3, workspace, 3
bind = $mod, 4, workspace, 4
bind = $mod, 5, workspace, 5
bind = $mod SHIFT, 1, movetoworkspace, 1
bind = $mod SHIFT, 2, movetoworkspace, 2
bind = $mod SHIFT, 3, movetoworkspace, 3
bind = $mod SHIFT, 4, movetoworkspace, 4
bind = $mod SHIFT, 5, movetoworkspace, 5

# Screenshots
bind = , PRINT, exec, grim -g "$(slurp)" - | wl-copy
bind = $mod, PRINT, exec, bash -lc 'mkdir -p "$HOME/Pictures/Screenshots"; grim -g "$(slurp)" "$HOME/Pictures/Screenshots/$(date +%F_%H-%M-%S).png"'

# Audio (PipeWire)
bind = , XF86AudioRaiseVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+
bind = , XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
bind = , XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
bind = , XF86AudioMicMute, exec, wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle

# Brightness
bind = , XF86MonBrightnessUp, exec, brightnessctl set +10%
bind = , XF86MonBrightnessDown, exec, brightnessctl set 10%-
HYPRCONF

cat > "${HYPR_DIR}/hyprpaper.conf" <<'PAPERCONF'
# Hyprpaper config (v2)
# Put your wallpaper at: ~/.config/hypr/wallpaper.jpg
preload = ~/.config/hypr/wallpaper.jpg
wallpaper = ,~/.config/hypr/wallpaper.jpg
PAPERCONF

# -------------------- GDM session entry (only if missing) --------------------
if [[ ! -f /usr/share/wayland-sessions/hyprland.desktop ]]; then
  echo "== Creating GDM session entry for Hyprland =="
  sudo tee /usr/share/wayland-sessions/hyprland.desktop >/dev/null <<'GDMEOF'
[Desktop Entry]
Name=Hyprland
Comment=Hyprland Wayland compositor
Exec=Hyprland
Type=Application
GDMEOF
fi

# -------------------- Final checks --------------------
echo "=== Hyprland install v2 completed ==="
echo "Next steps:"
echo "1) Logout -> in GDM click the gear icon -> choose Hyprland"
echo "2) SUPER+ENTER opens Kitty, SUPER+D opens Wofi"
echo "3) Keyboard layout toggle: Alt+Shift (latam/us)"
echo "4) If wallpaper is blank, place one at ~/.config/hypr/wallpaper.jpg"
