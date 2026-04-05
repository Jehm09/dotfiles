#!/usr/bin/env bash
# Install the Arch Linux base system via pacstrap.
# Also copies setup files and dotfiles into the new system so
# chroot scripts can access package lists and run symlinks.

set -Eeuo pipefail

mountpoint -q /mnt || {
    echo "ERROR: /mnt is not mounted. Run 1-preinstall.sh first."
    exit 1
}

# Resolve the dotfiles root (one level up from setup/)
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGES_FILE="$DOTFILES_DIR/packages/base.txt"

[[ -f "$PACKAGES_FILE" ]] || {
    echo "ERROR: Base package list not found: $PACKAGES_FILE"
    exit 1
}

# Parse packages: strip comments and blank lines, return one name per line
parse_packages() {
    grep -v '^\s*#' "$1" \
        | grep -v '^\s*$' \
        | awk '{print $1}' \
        | grep -v '^$'
}

mapfile -t BASE_PKGS < <(parse_packages "$PACKAGES_FILE")

echo "Installing base system (${#BASE_PKGS[@]} packages)..."
pacstrap /mnt "${BASE_PKGS[@]}"

# Generate /etc/fstab using UUIDs (stable across reboots)
echo "Generating /etc/fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

# Copy setup scripts and package lists into the new system
# 6-desktop.sh reads from /root/packages/ during chroot
echo "Copying setup files to new system..."
cp -r "$DOTFILES_DIR/setup"    /mnt/root/setup
cp -r "$DOTFILES_DIR/packages" /mnt/root/packages

# Copy the entire dotfiles repo to /root/dotfiles_src so 6-desktop.sh
# can install them into the user's home directory after the user is created
cp -r "$DOTFILES_DIR" /mnt/root/dotfiles_src

echo ""
echo "Base system installed."
