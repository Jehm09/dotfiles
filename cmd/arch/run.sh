#!/usr/bin/env bash
# Full Arch Linux install orchestrator.
# Sourced by the 'setup arch' subcommand. Must run as root from the Arch ISO.
#
# Sequence:
#   1. Optimize pacman mirrors
#   2. Disk partitioning, formatting, mounting
#   3. pacstrap base system + copy dotfiles to new system
#   4. Collect hostname / username / password
#   5. arch-chroot: system config, bootloader, hardware, desktop

set -Eeuo pipefail

LOG_FILE="${REPO_ROOT}/arch-install.log"
exec > >(tee "$LOG_FILE") 2>&1

echo "=== Arch Linux Installer ==="
echo "Log: $LOG_FILE"
echo ""

# ------------------------------------------------------------------
# 1. Optimize mirrors
# ------------------------------------------------------------------
echo "==> Optimizing mirrors..."
pacman -Sy --noconfirm reflector
reflector \
    --country Colombia,United_States \
    --age 12 \
    --protocol https \
    --sort rate \
    --save /etc/pacman.d/mirrorlist

# ------------------------------------------------------------------
# 2. Disk setup
# ------------------------------------------------------------------
echo "==> Disk setup..."
bash "$REPO_ROOT/cmd/arch/1-disk.sh"

# ------------------------------------------------------------------
# 3. Base system
# ------------------------------------------------------------------
echo "==> Installing base system..."
bash "$REPO_ROOT/cmd/arch/2-base.sh"

# ------------------------------------------------------------------
# 4. Collect install configuration
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
cat > /mnt/root/install.conf <<EOF
HOSTNAME="$HOSTNAME"
USERNAME="$USERNAME"
PASSWORD="$PASSWORD"
TIMEZONE="America/Bogota"
LOCALE="en_US.UTF-8"
KEYMAP="us"
EOF

# ------------------------------------------------------------------
# 5. arch-chroot: system, bootloader, hardware, desktop
# ------------------------------------------------------------------
echo "==> Entering arch-chroot..."
arch-chroot /mnt /bin/bash <<'CHROOT'
set -e
bash /root/dotfiles_src/cmd/arch/3-system.sh
bash /root/dotfiles_src/cmd/arch/4-bootloader.sh
bash /root/dotfiles_src/cmd/arch/5-hardware.sh
bash /root/dotfiles_src/cmd/arch/6-desktop.sh
# Clean up temporary files
cd /root
rm -f /root/install.conf
rm -rf /root/dotfiles_src
echo ""
echo "==> Installation complete. Log saved to $LOG_FILE"
echo ""
echo "Next steps:"
echo "  1.  umount -R /mnt"
echo "  2.  reboot"
echo "  3.  Log in — your dotfiles are already linked at ~/.config"
CHROOT
