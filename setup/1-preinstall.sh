#!/usr/bin/env bash
# Disk partitioning, formatting, and mounting.
# Run from the Arch ISO live environment as root.
#
# Override keyboard layout:  KEYMAP=la-latin1 ./1-preinstall.sh

set -Eeuo pipefail

KEYMAP="${KEYMAP:-us}"
EFI_SIZE="1024MiB"
ROOT_FS="ext4"

# ------------------------------------------------------------------
# Pre-flight checks
# ------------------------------------------------------------------
echo "Running pre-flight checks..."

[[ "$(uname -m)" == "x86_64" ]] || {
    echo "ERROR: Only x86_64 architecture is supported."
    exit 1
}

[[ -d /sys/firmware/efi ]] || {
    echo "ERROR: UEFI mode not detected. This installer requires UEFI."
    exit 1
}

ping -c 1 archlinux.org >/dev/null 2>&1 || {
    echo "ERROR: No internet connection. Check your network and retry."
    exit 1
}

# ------------------------------------------------------------------
# Initial setup
# ------------------------------------------------------------------
echo "Setting keyboard layout: $KEYMAP"
loadkeys "$KEYMAP"

echo "Syncing system clock..."
timedatectl set-ntp true

# ------------------------------------------------------------------
# Disk selection
# ------------------------------------------------------------------
echo ""
echo "Available disks:"
lsblk -d -o NAME,SIZE,MODEL
echo ""

mapfile -t DISKS < <(lsblk -d -n -o NAME)

PS3="Select the disk to install Arch Linux on: "
select DISK in "${DISKS[@]}"; do
    [[ -n "$DISK" ]] && break
done

TARGET="/dev/$DISK"

echo ""
echo "WARNING: All data on $TARGET will be PERMANENTLY DESTROYED."
read -rp "Type 'yes' to confirm: " CONFIRM

[[ "$CONFIRM" == "yes" ]] || {
    echo "Aborted."
    exit 1
}

# ------------------------------------------------------------------
# Partitioning
# ------------------------------------------------------------------
echo "Wiping existing signatures on $TARGET..."
wipefs -af "$TARGET"

echo "Creating GPT partition table..."
parted -s "$TARGET" mklabel gpt

# EFI System Partition (ESP) - where the bootloader lives
echo "Creating EFI partition (${EFI_SIZE})..."
parted -s "$TARGET" mkpart ESP fat32 1MiB "$EFI_SIZE"
parted -s "$TARGET" set 1 esp on

# Root partition - remainder of disk
echo "Creating root partition (remaining space)..."
parted -s "$TARGET" mkpart primary "$ROOT_FS" "$EFI_SIZE" 100%

# Force kernel to re-read the new partition table
partprobe "$TARGET"
sleep 2

# ------------------------------------------------------------------
# Resolve partition names
# ------------------------------------------------------------------
# NVMe and MMC devices use a 'p' prefix for partition numbers
# e.g. /dev/nvme0n1p1 vs /dev/sda1
if [[ "$TARGET" =~ [0-9]$ ]]; then
    EFI_PART="${TARGET}p1"
    ROOT_PART="${TARGET}p2"
else
    EFI_PART="${TARGET}1"
    ROOT_PART="${TARGET}2"
fi

# ------------------------------------------------------------------
# Formatting
# ------------------------------------------------------------------
echo "Formatting EFI partition as FAT32..."
mkfs.fat -F32 "$EFI_PART"

echo "Formatting root partition as $ROOT_FS..."
mkfs."$ROOT_FS" -F "$ROOT_PART"

# ------------------------------------------------------------------
# Mounting
# ------------------------------------------------------------------
echo "Mounting filesystems..."
mount "$ROOT_PART" /mnt
mkdir -p /mnt/boot
mount "$EFI_PART" /mnt/boot

echo ""
echo "Pre-install complete. Partitions mounted at /mnt."
