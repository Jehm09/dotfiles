#!/usr/bin/env bash
# Install the Arch Linux base system via pacstrap.
# Also copies the entire dotfiles repo into the new system so
# chroot scripts can access package lists, libraries, and run symlinks.

set -Eeuo pipefail

mountpoint -q /mnt || {
    echo "ERROR: /mnt is not mounted. Run 1-disk.sh first."
    exit 1
}

# REPO_ROOT is set by cmd/arch/run.sh (sourced via setup)
PACKAGES_FILE="$REPO_ROOT/packages/base.conf"

[[ -f "$PACKAGES_FILE" ]] || {
    echo "ERROR: Base package list not found: $PACKAGES_FILE"
    exit 1
}

# Parse packages: strip comments and blank lines, return one name per line
parse_packages() {
    grep -v '^\s*#' "$1" \
        | grep -v '^\s*##' \
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

# Copy the entire dotfiles repo into the new system.
# Chroot scripts access packages, lib/, and cmd/ from /root/dotfiles_src/.
echo "Copying dotfiles to new system..."
cp -r "$REPO_ROOT" /mnt/root/dotfiles_src

echo ""
echo "Base system installed."
