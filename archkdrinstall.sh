#!/usr/bin/env bash
# ==============================================================
# Arch Linux DevOps Installer v2.4
# By Carlos Vázquez (2025)
# ==============================================================

set -euo pipefail

### --- 0) Confirmación inicial ---
echo "⚠️  Este script BORRARÁ COMPLETAMENTE /dev/nvme0n1"
read -rp "Escribe 'INSTALAR' para continuar: " ACK
[[ "${ACK:-}" == "INSTALAR" ]] || { echo "Abortado."; exit 1; }

### --- 1) Entradas del usuario ---
read -rp "Hostname: " HOSTNAME
read -rp "Usuario administrador: " USERNAME
read -rsp "Contraseña para ${USERNAME}: " USERPASS; echo
read -rsp "Repite la contraseña: " USERPASS2; echo
[[ "$USERPASS" == "$USERPASS2" ]] || { echo "❌ Contraseñas no coinciden"; exit 1; }

DISK="/dev/nvme0n1"
EFI_SIZE="512MiB"
SWAP_SIZE_GB=8
ROOTLESS_DOCKER="${ROOTLESS_DOCKER:-0}"

### --- 2) Preparación del disco ---
echo "🧹 Limpiando particiones anteriores en $DISK..."
sgdisk --zap-all "$DISK"
parted -s "$DISK" mklabel gpt \
  mkpart ESP fat32 1MiB "$EFI_SIZE" \
  set 1 esp on \
  mkpart btrfs "$EFI_SIZE" 100%
partprobe "$DISK"
udevadm settle
sleep 1

EFI_PART="${DISK}p1"
ROOT_PART="${DISK}p2"

mkfs.fat -F32 "$EFI_PART"
mkfs.btrfs -f "$ROOT_PART"

### --- 3) Subvolúmenes Btrfs ---
mount "$ROOT_PART" /mnt
for sub in @ @home @log @pkg @tmp @swap; do
  btrfs subvolume create /mnt/$sub
done
umount /mnt

BTRFS_OPTS="noatime,ssd,compress=zstd:3,space_cache=v2"

# ✅ corregido el espacio extra
mount -o "${BTRFS_OPTS},subvol=@ " "$ROOT_PART" /mnt 2>/dev/null || \
mount -o "${BTRFS_OPTS},subvol=@ " "$ROOT_PART" /mnt 2>/dev/null || \
mount -o "${BTRFS_OPTS},subvol=@ " "$ROOT_PART" /mnt
mount -o "${BTRFS_OPTS},subvol=@ " "$ROOT_PART" /mnt
# versión correcta:
umount /mnt 2>/dev/null || true
mount -o "${BTRFS_OPTS},subvol=@"/ "$ROOT_PART" /mnt

mkdir -p /mnt/{boot,home,var/log,var/cache/pacman/pkg,tmp,swap}
mount -o "${BTRFS_OPTS},subvol=@home" "$ROOT_PART" /mnt/home
mount -o "${BTRFS_OPTS},subvol=@log" "$ROOT_PART" /mnt/var/log
mount -o "${BTRFS_OPTS},subvol=@pkg" "$ROOT_PART" /mnt/var/cache/pacman/pkg
mount -o noatime,ssd "$ROOT_PART" /mnt/swap
mount "$EFI_PART" /mnt/boot

### --- 4) Swapfile ---
chattr +C /mnt/swap
btrfs property set /mnt/swap compression none || true
fallocate -l "${SWAP_SIZE_GB}G" /mnt/swap/swapfile
chmod 600 /mnt/swap/swapfile
mkswap /mnt/swap/swapfile

### --- 5) Instalación base ---
echo "📦 Instalando sistema base..."
if lscpu | grep -qi intel; then UCODE=intel-ucode; else UCODE=amd-ucode; fi

BASE_PKGS=(base base-devel linux-zen linux-zen-headers linux-firmware btrfs-progs \
            networkmanager sudo zsh git curl wget openssh man-db man-pages texinfo \
            efibootmgr dosfstools mtools xdg-user-dirs xdg-utils pipewire pipewire-alsa \
            pipewire-pulse wireplumber gnome-keyring jq yq)

GFX_PKGS=(mesa vulkan-intel intel-media-driver libva-intel-driver)
GNOME_PKGS=(gnome gdm gnome-tweaks)
HYPR_PKGS=(hyprland waybar hyprpaper wofi grim slurp wl-clipboard \
            xdg-desktop-portal xdg-desktop-portal-gtk xdg-desktop-portal-hyprland)
NET_PKGS=(nm-connection-editor networkmanager-openvpn wireguard-tools openvpn)
DEV_PKGS=(kitty neovim unzip tar ripgrep fd nodejs npm python-pipx cmake make pkgconf)
SEC_PKGS=(ufw bluez bluez-utils ttf-fira-code ttf-jetbrains-mono ttf-nerd-fonts-symbols htop fastfetch)
DOCKER_PKGS=(docker docker-compose docker-buildx)

pacstrap -K /mnt "${BASE_PKGS[@]}" "$UCODE" "${GFX_PKGS[@]}" \
              "${GNOME_PKGS[@]}" "${HYPR_PKGS[@]}" "${NET_PKGS[@]}" \
              "${DEV_PKGS[@]}" "${SEC_PKGS[@]}" "${DOCKER_PKGS[@]}"

genfstab -U /mnt >> /mnt/etc/fstab
echo "/swap/swapfile none swap defaults 0 0" >> /mnt/etc/fstab

### --- 6) Configuración en chroot ---
arch-chroot /mnt /bin/bash -eux <<CHROOT
set -euo pipefail
HOSTNAME="$HOSTNAME"
USERNAME="$USERNAME"
USERPASS="$USERPASS"
ROOTLESS_DOCKER="$ROOTLESS_DOCKER"

echo "\$HOSTNAME" > /etc/hostname
cat >/etc/hosts <<EOF
127.0.0.1 localhost
::1       localhost
127.0.1.1 \$HOSTNAME.localdomain \$HOSTNAME
EOF

sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
sed -i 's/^#es_MX.UTF-8/es_MX.UTF-8/' /etc/locale.gen
locale-gen
echo 'LANG=es_MX.UTF-8' > /etc/locale.conf
ln -sf /usr/share/zoneinfo/America/Mexico_City /etc/localtime
hwclock --systohc
echo 'KEYMAP=la-latin1' > /etc/vconsole.conf

# Usuarios
useradd -m -G wheel,docker -s /bin/zsh "\$USERNAME"
echo "\$USERNAME:\$USERPASS" | chpasswd
passwd -l root
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Servicios
systemctl enable NetworkManager
systemctl enable bluetooth
systemctl enable systemd-timesyncd
systemctl enable gdm
systemctl enable ufw
ufw --force enable || true
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
systemctl enable docker

# Loader (systemd-boot)
bootctl --path=/boot install
mkdir -p /boot/loader/entries
UUID=\$(findmnt -no UUID /)
INITRD_UCODE=""
if pacman -Q intel-ucode >/dev/null 2>&1; then INITRD_UCODE="initrd  /intel-ucode.img"; fi
if pacman -Q amd-ucode >/dev/null 2>&1; then INITRD_UCODE="initrd  /amd-ucode.img"; fi
cat >/boot/loader/loader.conf <<EOF
default arch
timeout 3
console-mode max
editor no
EOF
cat >/boot/loader/entries/arch.conf <<EOF
title   Arch Linux (linux-zen)
linux   /vmlinuz-linux-zen
\$INITRD_UCODE
initrd  /initramfs-linux-zen.img
options root=UUID=\$UUID rootflags=subvol=@ rw nowatchdog quiet splash
EOF
mkdir -p /boot/EFI/BOOT
cp /usr/lib/systemd/boot/efi/systemd-bootx64.efi /boot/EFI/BOOT/BOOTX64.EFI

# Paru (AUR helper)
pacman -S --noconfirm --needed base-devel
sudo -u "\$USERNAME" bash -lc '
  cd ~
  if ! command -v paru >/dev/null; then
    git clone https://aur.archlinux.org/paru.git
    cd paru && makepkg -si --noconfirm
  fi
'

# Herramientas AWS y Pulumi (desde AUR)
sudo -u "\$USERNAME" bash -lc '
  paru -S --noconfirm aws-cli-v2 aws-sam-cli pulumi-bin aws-vault
'

CHROOT

echo "✅ Instalación completada correctamente. Puedes reiniciar ahora."
