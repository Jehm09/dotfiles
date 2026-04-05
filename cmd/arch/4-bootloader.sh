#!/usr/bin/env bash
# Install and configure GRUB as the UEFI bootloader.
# Supports dual boot: detects Windows and other Linux installs via os-prober.
#
# Called by cmd/arch/run.sh via arch-chroot.

set -Eeuo pipefail

DOTFILES="/root/dotfiles_src"
source "$DOTFILES/lib/utils.sh"

# ------------------------------------------------------------------
# Pre-flight checks
# ------------------------------------------------------------------
[[ -d /sys/firmware/efi ]] || {
    error "UEFI firmware directory not found. Is this a UEFI system?"
    exit 1
}

[[ -d /boot ]] || {
    error "/boot directory not found."
    exit 1
}

BOOT_FS=$(findmnt -n -o FSTYPE /boot)
[[ "$BOOT_FS" == "vfat" ]] || {
    error "/boot is not a FAT32 EFI partition (found: $BOOT_FS)."
    exit 1
}

# ------------------------------------------------------------------
# Install packages
# ------------------------------------------------------------------
info "Installing GRUB and related tools..."
pacman -S --needed --noconfirm \
    grub       \
    efibootmgr \
    os-prober  \
    ntfs-3g

# ------------------------------------------------------------------
# Enable os-prober (detects Windows and other OSes)
# ------------------------------------------------------------------
sed -i 's/^#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub

# ------------------------------------------------------------------
# Install GRUB to the EFI partition
# ------------------------------------------------------------------
info "Installing GRUB to EFI partition..."
grub-install \
    --target=x86_64-efi \
    --efi-directory=/boot \
    --bootloader-id=GRUB \
    --recheck

# ------------------------------------------------------------------
# Generate GRUB configuration
# ------------------------------------------------------------------
info "Generating GRUB config..."
os-prober || true   # non-fatal: no other OS found is acceptable
sleep 2
grub-mkconfig -o /boot/grub/grub.cfg

echo ""
success "Bootloader installed. Windows will be detected automatically if present."
