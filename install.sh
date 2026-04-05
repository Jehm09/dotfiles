#!/usr/bin/env bash
# Arch Linux full installation script.
# Run from the Arch ISO live environment as root.
#
# This script is fully automated from disk partitioning to a complete
# graphical desktop. After it finishes, just reboot.
#
# For an existing Arch Linux install that only needs the graphical
# setup (Hyprland + Quickshell + dotfiles), use install-desktop.sh instead.

set -Eeuo pipefail

LOG_FILE="install.log"
exec > >(tee "$LOG_FILE") 2>&1

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

chmod +x "$DOTFILES_DIR"/setup/*.sh
chmod +x "$DOTFILES_DIR"/scripts/*.sh 2>/dev/null || true

echo "Arch Linux installer"
echo "Log: $LOG_FILE"
echo ""

# ------------------------------------------------------------------
# Optimise pacman mirrors
# ------------------------------------------------------------------
echo "==> Optimising mirrors..."
pacman -Sy --noconfirm reflector
reflector \
    --country Colombia,United_States \
    --age 12 \
    --protocol https \
    --sort rate \
    --save /etc/pacman.d/mirrorlist

# ------------------------------------------------------------------
# Step 1: Partition, format, mount
# ------------------------------------------------------------------
echo "==> Step 1: Disk setup"
"$DOTFILES_DIR/setup/1-preinstall.sh"

# ------------------------------------------------------------------
# Step 2: pacstrap base system
# (also copies setup/, packages/, and dotfiles to /mnt/root/)
# ------------------------------------------------------------------
echo "==> Step 2: Base system"
"$DOTFILES_DIR/setup/2-base.sh"

# ------------------------------------------------------------------
# Collect install configuration
# ------------------------------------------------------------------
echo ""
echo "==> System configuration"
read -rp  "Hostname: "         HOSTNAME
read -rp  "Primary username: " USERNAME

echo "Password for $USERNAME and root:"
read -rsp "Password: "          PASSWORD
echo
read -rsp "Confirm password: "  PASSWORD_CONFIRM
echo

[[ "$PASSWORD" == "$PASSWORD_CONFIRM" ]] || {
    echo "ERROR: Passwords do not match."
    exit 1
}

# Write config so all chroot scripts can source it
cat > /mnt/root/setup/install.conf <<EOF
HOSTNAME="$HOSTNAME"
USERNAME="$USERNAME"
PASSWORD="$PASSWORD"
TIMEZONE="America/Bogota"
LOCALE="en_US.UTF-8"
KEYMAP="us"
EOF

# ------------------------------------------------------------------
# Steps 3-6: Configure the new system inside arch-chroot
#
#   3-chroot.sh    locale, hostname, users, services
#   4-bootloader.sh  GRUB UEFI
#   5-hardware.sh  CPU microcode, Wi-Fi, Bluetooth, PipeWire, GPU drivers
#   6-desktop.sh   desktop packages, yay, AUR packages, dotfile symlinks
# ------------------------------------------------------------------
echo "==> Entering arch-chroot for full system configuration..."
arch-chroot /mnt /bin/bash <<'CHROOT'
set -e
cd /root/setup
chmod +x *.sh
./3-chroot.sh
./4-bootloader.sh
./5-hardware.sh
./6-desktop.sh
# Clean up temporary files copied during installation
rm -f install.conf
rm -rf /root/dotfiles_src
CHROOT

echo ""
echo "==> Installation complete. Log saved to $LOG_FILE"
echo ""
echo "Next steps:"
echo "  1.  umount -R /mnt"
echo "  2.  reboot"
echo "  3.  Log in — your dotfiles are already linked at ~/.config"
