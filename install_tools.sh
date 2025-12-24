#!/usr/bin/env bash
set -euo pipefail

echo "=== ARCH POST INSTALL (uv + pulumi) ==="

# 1) Update
sudo pacman -Syu --noconfirm

# 2) Base build tooling (needed for AUR builds)
sudo pacman -S --noconfirm --needed base-devel git curl ca-certificates

# 3) Install paru (AUR helper) if missing
if ! command -v paru >/dev/null 2>&1; then
  rm -rf /tmp/paru >/dev/null 2>&1 || true
  git clone https://aur.archlinux.org/paru.git /tmp/paru
  (cd /tmp/paru && makepkg -si --noconfirm)
fi

# 4) Core DevOps tools (official repos)
sudo pacman -S --noconfirm --needed \
  docker docker-compose docker-buildx \
  jq yq \
  openssh \
  unzip zip \
  ripgrep fd \
  neovim

# Enable docker and add user to docker group
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"

# 5) Python runtime (no pip workflow; uv will manage envs)
sudo pacman -S --noconfirm --needed python

# 6) Install uv (Astral) to ~/.local/bin and ensure PATH (zsh)
if ! command -v uv >/dev/null 2>&1; then
  curl -LsSf https://astral.sh/uv/install.sh | sh
fi

# Ensure ~/.local/bin is on PATH for Zsh sessions (interactive + login)
ZSHRC="$HOME/.zshrc"
ZPROFILE="$HOME/.zprofile"
LINE='export PATH="$HOME/.local/bin:$PATH"'

grep -qxF "$LINE" "$ZSHRC" 2>/dev/null || echo "$LINE" >> "$ZSHRC"
grep -qxF "$LINE" "$ZPROFILE" 2>/dev/null || echo "$LINE" >> "$ZPROFILE"

# Load PATH for current shell execution (this script)
export PATH="$HOME/.local/bin:$PATH"

# 7) Pulumi (AUR)
# Use pulumi-bin to avoid building from source.
paru -S --noconfirm --needed pulumi-bin

# 8) (Optional but recommended for AWS users)
# Uncomment if you want AWS CLI v2 from AUR:
# paru -S --noconfirm --needed aws-cli-v2-bin

echo "=== DONE ==="
echo "Notes:"
echo "- Abre una nueva terminal o ejecuta: source ~/.zshrc"
echo "- Verifica: uv --version"
echo "- Verifica: pulumi version"
echo "- Para Docker sin sudo: cierra sesión y vuelve a entrar (grupo docker)"
