#!/usr/bin/env bash
# Install and configure GRUB as the UEFI bootloader.
# Supports dual boot: detects Windows and other Linux installs via os-prober.

set -Eeuo pipefail

# ------------------------------------------------------------------
# Pre-flight checks
# ------------------------------------------------------------------
[[ -d /sys/firmware/efi ]] || {
    echo "ERROR: UEFI firmware directory not found. Is this a UEFI system?"
    exit 1
}

[[ -d /boot ]] || {
    echo "ERROR: /boot directory not found."
    exit 1
}

BOOT_FS=$(findmnt -n -o FSTYPE /boot)
[[ "$BOOT_FS" == "vfat" ]] || {
    echo "ERROR: /boot is not a FAT32 EFI partition (found: $BOOT_FS)."
    exit 1
}

# ------------------------------------------------------------------
# Install packages
# ------------------------------------------------------------------
echo "Installing GRUB and related tools..."
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
echo "Installing GRUB to EFI partition..."
grub-install \
    --target=x86_64-efi \
    --efi-directory=/boot \
    --bootloader-id=GRUB \
    --recheck

# ------------------------------------------------------------------
# Generate GRUB configuration
# ------------------------------------------------------------------
echo "Generating GRUB config..."
os-prober || true   # non-fatal: no other OS found is acceptable
sleep 2
grub-mkconfig -o /boot/grub/grub.cfg

echo ""
echo "Bootloader installed. Windows will be detected automatically if present."
