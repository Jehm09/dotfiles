#!/usr/bin/env bash
# Disk partitioning, formatting, and mounting.
# Run from the Arch ISO live environment as root.
#
# Override keyboard layout:  KEYMAP=la-latin1 ./setup arch

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
# Disk / partition overview
# ------------------------------------------------------------------
echo ""
echo "Current block devices:"
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT
echo ""

# ------------------------------------------------------------------
# Install mode selection
# ------------------------------------------------------------------
echo "Install mode:"
echo "  1) Whole disk  — erase everything and partition from scratch"
echo "  2) Existing partition  — use a free partition (dual-boot / Windows)"
echo ""
read -rp "Select mode [1/2]: " MODE

case "$MODE" in
    1)
        # ── Whole-disk mode ───────────────────────────────────────────
        mapfile -t DISKS < <(lsblk -d -n -o NAME)

        echo ""
        PS3="Select the disk to install Arch Linux on: "
        select DISK in "${DISKS[@]}"; do
            [[ -n "$DISK" ]] && break
        done

        TARGET="/dev/$DISK"

        echo ""
        echo "WARNING: All data on $TARGET will be PERMANENTLY DESTROYED."
        read -rp "Type 'yes' to confirm: " CONFIRM
        [[ "$CONFIRM" == "yes" ]] || { echo "Aborted."; exit 1; }

        # ── Partitioning ──────────────────────────────────────────────
        echo "Wiping existing signatures on $TARGET..."
        wipefs -af "$TARGET"

        echo "Creating GPT partition table..."
        parted -s "$TARGET" mklabel gpt

        echo "Creating EFI partition (${EFI_SIZE})..."
        parted -s "$TARGET" mkpart ESP fat32 1MiB "$EFI_SIZE"
        parted -s "$TARGET" set 1 esp on

        echo "Creating root partition (remaining space)..."
        parted -s "$TARGET" mkpart primary "$ROOT_FS" "$EFI_SIZE" 100%

        partprobe "$TARGET"
        sleep 2

        # NVMe/MMC use 'p' prefix: /dev/nvme0n1p1 vs /dev/sda1
        if [[ "$TARGET" =~ [0-9]$ ]]; then
            EFI_PART="${TARGET}p1"
            ROOT_PART="${TARGET}p2"
        else
            EFI_PART="${TARGET}1"
            ROOT_PART="${TARGET}2"
        fi

        echo "Formatting EFI partition as FAT32..."
        mkfs.fat -F32 "$EFI_PART"

        echo "Formatting root partition as $ROOT_FS..."
        mkfs."$ROOT_FS" -F "$ROOT_PART"
        ;;

    2)
        # ── Existing-partition mode (dual-boot) ───────────────────────
        echo ""
        echo "Available partitions:"
        lsblk -n -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT | awk '$0 !~ /^[a-z]/ || /part/ { print }'
        echo ""

        # Build list of all partitions
        mapfile -t PARTS < <(lsblk -n -o NAME,TYPE | awk '$2=="part"{print $1}')

        echo "Select the FREE partition to use as Arch root (will be formatted as $ROOT_FS):"
        PS3="Root partition: "
        select PART in "${PARTS[@]}"; do
            [[ -n "$PART" ]] && break
        done
        ROOT_PART="/dev/$PART"

        echo ""
        echo "WARNING: $ROOT_PART will be formatted. All data on it will be lost."
        read -rp "Type 'yes' to confirm: " CONFIRM
        [[ "$CONFIRM" == "yes" ]] || { echo "Aborted."; exit 1; }

        # EFI partition — list vfat partitions as likely candidates
        echo ""
        echo "EFI (ESP) partition candidates (vfat / type EF00):"
        lsblk -n -o NAME,SIZE,FSTYPE,PARTTYPE | \
            awk '$3=="vfat" || $4=="c12a7328-f81f-11d2-ba4b-00a0c93ec93b" {print NR") "$0}'
        echo ""

        mapfile -t EFI_CANDIDATES < <(lsblk -n -o NAME,FSTYPE,PARTTYPE | \
            awk '$2=="vfat" || $3=="c12a7328-f81f-11d2-ba4b-00a0c93ec93b" {print $1}')

        if [[ ${#EFI_CANDIDATES[@]} -gt 0 ]]; then
            PS3="Select existing EFI partition (or 0 to enter manually): "
            select EFI_NAME in "${EFI_CANDIDATES[@]}" "Enter manually"; do
                if [[ "$EFI_NAME" == "Enter manually" ]]; then
                    read -rp "EFI partition (e.g. sda1, nvme0n1p1): " EFI_NAME
                fi
                [[ -n "$EFI_NAME" ]] && break
            done
        else
            echo "No vfat partition detected. Enter the EFI partition name manually."
            read -rp "EFI partition (e.g. sda1, nvme0n1p1): " EFI_NAME
        fi
        EFI_PART="/dev/$EFI_NAME"

        [[ -b "$EFI_PART" ]] || { echo "ERROR: $EFI_PART does not exist."; exit 1; }
        [[ -b "$ROOT_PART" ]] || { echo "ERROR: $ROOT_PART does not exist."; exit 1; }

        echo ""
        echo "Plan:"
        echo "  EFI  → $EFI_PART  (will be mounted, NOT reformatted)"
        echo "  Root → $ROOT_PART  (will be formatted as $ROOT_FS)"
        read -rp "Proceed? [yes/N]: " CONFIRM2
        [[ "$CONFIRM2" == "yes" ]] || { echo "Aborted."; exit 1; }

        echo "Formatting root partition as $ROOT_FS..."
        mkfs."$ROOT_FS" -F "$ROOT_PART"
        ;;

    *)
        echo "Invalid option. Aborted."
        exit 1
        ;;
esac

# ------------------------------------------------------------------
# Mounting (common to both modes)
# ------------------------------------------------------------------
echo "Mounting filesystems..."
mount "$ROOT_PART" /mnt
mkdir -p /mnt/boot
mount "$EFI_PART" /mnt/boot

echo ""
echo "Pre-install complete. Partitions mounted at /mnt."
