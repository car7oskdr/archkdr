#!/usr/bin/env bash
set -euo pipefail

### ================= CONFIG =================
DISK="/dev/nvme0n1"
EFI_SIZE="512M"
TIMEZONE="America/Mexico_City"
LOCALE_MAIN="en_US.UTF-8"
LOCALE_EXTRA="es_MX.UTF-8"
KEYMAP="la-latin1"
KERNEL="linux-zen"
### ==========================================

echo "=== ARCH LINUX BASE INSTALL ==="

read -rp "Hostname: " HOSTNAME
read -rp "Usuario: " USERNAME
read -rsp "Password usuario: " USER_PASS; echo
read -rsp "Confirmar password: " USER_PASS2; echo
[[ "$USER_PASS" != "$USER_PASS2" ]] && { echo "Passwords no coinciden"; exit 1; }

timedatectl set-ntp true
loadkeys "$KEYMAP"

### ---------- DISK ----------
wipefs -af "$DISK"
sgdisk -Z "$DISK"

parted -s "$DISK" mklabel gpt
parted -s "$DISK" mkpart ESP fat32 1MiB "$EFI_SIZE"
parted -s "$DISK" set 1 esp on
parted -s "$DISK" mkpart ROOT btrfs "$EFI_SIZE" 100%

mkfs.fat -F32 "${DISK}p1"
mkfs.btrfs -f "${DISK}p2"

### ---------- BTRFS ----------
mount "${DISK}p2" /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@log
btrfs subvolume create /mnt/@pkg
umount /mnt

mount -o noatime,compress=zstd,subvol=@ "${DISK}p2" /mnt
mkdir -p /mnt/{boot,home,var/log,var/cache/pacman/pkg}
mount -o noatime,compress=zstd,subvol=@home "${DISK}p2" /mnt/home
mount -o noatime,compress=zstd,subvol=@log "${DISK}p2" /mnt/var/log
mount -o noatime,compress=zstd,subvol=@pkg "${DISK}p2" /mnt/var/cache/pacman/pkg
mount "${DISK}p1" /mnt/boot

### ---------- BASE SYSTEM ----------
pacstrap -K /mnt \
  base base-devel \
  "$KERNEL" linux-firmware sof-firmware \
  btrfs-progs \
  networkmanager \
  pipewire pipewire-pulse wireplumber \
  intel-ucode \
  nvidia nvidia-utils nvidia-prime \
  gnome gdm \
  sudo vim git curl wget \
  zsh kitty

genfstab -U /mnt >> /mnt/etc/fstab

### ---------- CHROOT ----------
arch-chroot /mnt /bin/bash <<EOF
set -e

ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

sed -i "s/#$LOCALE_MAIN/$LOCALE_MAIN/" /etc/locale.gen
sed -i "s/#$LOCALE_EXTRA/$LOCALE_EXTRA/" /etc/locale.gen
locale-gen

echo "LANG=$LOCALE_MAIN" > /etc/locale.conf
echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf

echo "$HOSTNAME" > /etc/hostname
cat > /etc/hosts <<HOSTS
127.0.0.1 localhost
::1 localhost
127.0.1.1 $HOSTNAME.localdomain $HOSTNAME
HOSTS

useradd -m -G wheel -s /bin/zsh $USERNAME
echo "$USERNAME:$USER_PASS" | chpasswd
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

bootctl install
cat > /boot/loader/loader.conf <<LOADER
default arch
timeout 3
editor no
LOADER

cat > /boot/loader/entries/arch.conf <<ENTRY
title Arch Linux
linux /vmlinuz-$KERNEL
initrd /intel-ucode.img
initrd /initramfs-$KERNEL.img
options root=${DISK}p2 rootflags=subvol=@ rw quiet loglevel=3
ENTRY

echo "options snd-intel-dspcfg dsp_driver=3" > /etc/modprobe.d/sof.conf

systemctl enable NetworkManager gdm

EOF

echo "=== BASE INSTALL COMPLETE ==="
echo "Reboot, login as $USERNAME, then run post-install script"
