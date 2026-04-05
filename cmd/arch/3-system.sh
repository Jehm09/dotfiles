#!/usr/bin/env bash
# System configuration inside arch-chroot.
# Sets up locale, timezone, hostname, users, and essential services.
#
# Called by cmd/arch/run.sh via arch-chroot. Expects /root/install.conf to exist.

set -Eeuo pipefail

DOTFILES="/root/dotfiles_src"
source "$DOTFILES/lib/utils.sh"
source /root/install.conf

# Sync package database
pacman -Sy --noconfirm

# ------------------------------------------------------------------
# Timezone
# ------------------------------------------------------------------
info "Setting timezone: $TIMEZONE"
ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
hwclock --systohc

# ------------------------------------------------------------------
# Locale
# ------------------------------------------------------------------
info "Configuring locale: $LOCALE"
sed -i "s/^#\($LOCALE UTF-8\)/\1/" /etc/locale.gen
locale-gen
echo "LANG=$LOCALE" > /etc/locale.conf

# ------------------------------------------------------------------
# Console keyboard layout
# ------------------------------------------------------------------
echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf

# ------------------------------------------------------------------
# Hostname
# ------------------------------------------------------------------
echo "$HOSTNAME" > /etc/hostname
cat > /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
EOF

# ------------------------------------------------------------------
# Passwords
# ------------------------------------------------------------------
info "Setting root password..."
echo "root:$PASSWORD" | chpasswd

# ------------------------------------------------------------------
# Primary user
# ------------------------------------------------------------------
info "Creating user: $USERNAME"
# -m  : create home directory
# -G  : add to wheel group (sudo access)
# -s  : default shell (will be changed to fish by 6-desktop.sh)
useradd -m -G wheel -s /bin/bash "$USERNAME"
echo "$USERNAME:$PASSWORD" | chpasswd

# Grant sudo access to the wheel group
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# ------------------------------------------------------------------
# Essential services
# ------------------------------------------------------------------
info "Enabling essential services..."
systemctl enable NetworkManager

echo ""
success "Base system configured."
