#!/usr/bin/env bash
# Bootstrap the yay AUR helper if not already installed.
# yay is required to install packages from the Arch User Repository.

set -Eeuo pipefail

if command -v yay &>/dev/null; then
    echo "yay is already installed ($(yay --version | head -n1)), skipping"
    exit 0
fi

echo "Installing yay AUR helper..."

# base-devel and git are required to build AUR packages
sudo pacman -S --needed --noconfirm base-devel git

# Clone and build yay in a temporary directory that is cleaned up on exit
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

git clone https://aur.archlinux.org/yay.git "$TMPDIR/yay"
cd "$TMPDIR/yay"
makepkg -si --noconfirm

echo "yay installed: $(yay --version | head -n1)"
