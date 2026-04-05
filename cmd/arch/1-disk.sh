#!/usr/bin/env bash
# Disk partitioning, formatting, and mounting.
# Run from the Arch ISO live environment as root.
#
# Override keyboard layout:  KEYMAP=la-latin1 ./setup arch

set -Eeuo pipefail

KEYMAP="${KEYMAP:-us}"
EFI_SIZE="1024MiB"
ROOT_FS="ext4"

# Partition variables (set by whichever mode runs)
EFI_PART=""
ROOT_PART=""

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
# Helper: pick one partition from the global PARTS array
#   pick_partition <prompt> [optional]
#   Prints the /dev/... path, or empty string if skipped (optional only)
# ------------------------------------------------------------------
pick_partition() {
    local prompt="$1"
    local optional="${2:-no}"
    local choices=("${PARTS[@]}")
    [[ "$optional" == "yes" ]] && choices+=("(skip)")

    PS3="$prompt: "
    local chosen
    select chosen in "${choices[@]}"; do
        [[ -n "$chosen" ]] && break
    done

    if [[ "$chosen" == "(skip)" ]]; then
        echo ""
    else
        echo "/dev/$chosen"
    fi
}

# ------------------------------------------------------------------
# Install mode selection
# ------------------------------------------------------------------
echo "Install mode:"
echo "  1) Whole disk        — erase everything and partition from scratch"
echo "  2) Existing partitions — assign roles to existing partitions (dual-boot / reuse Linux layout)"
echo ""
read -rp "Select mode [1/2]: " MODE

case "$MODE" in
    # ── MODE 1: whole disk ─────────────────────────────────────────────
    1)
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

        # NVMe/MMC: /dev/nvme0n1p1, regular: /dev/sda1
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

    # ── MODE 2: assign existing partitions ────────────────────────────
    2)
        mapfile -t PARTS < <(lsblk -n -o NAME,TYPE | awk '$2=="part"{print $1}')

        if [[ ${#PARTS[@]} -eq 0 ]]; then
            echo "ERROR: No partitions found."
            exit 1
        fi

        echo ""
        echo "Partitions available:"
        lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT | grep -v "^loop"
        echo ""

        # ── Root (required) ───────────────────────────────────────────
        echo "── ROOT ──"
        ROOT_PART=$(pick_partition "Select root partition")
        [[ -b "$ROOT_PART" ]] || { echo "ERROR: invalid partition."; exit 1; }
        read -rp "Format $ROOT_PART as $ROOT_FS? [Y/n]: " fmt_root
        FORMAT_ROOT=true
        [[ "$fmt_root" =~ ^[Nn]$ ]] && FORMAT_ROOT=false

        # ── EFI (required) ────────────────────────────────────────────
        echo ""
        echo "── EFI / boot ──"
        EFI_PART=$(pick_partition "Select EFI partition")
        [[ -b "$EFI_PART" ]] || { echo "ERROR: invalid partition."; exit 1; }
        read -rp "Format $EFI_PART as FAT32? (say 'n' to reuse existing EFI) [y/N]: " fmt_efi
        FORMAT_EFI=false
        [[ "$fmt_efi" =~ ^[Yy]$ ]] && FORMAT_EFI=true

        # ── Confirm plan ──────────────────────────────────────────────
        echo ""
        echo "── Plan ─────────────────────────────────────────────────────"
        $FORMAT_ROOT \
            && echo "  /      → $ROOT_PART   format as $ROOT_FS" \
            || echo "  /      → $ROOT_PART   mount only (no format)"
        $FORMAT_EFI \
            && echo "  /boot  → $EFI_PART   format as FAT32" \
            || echo "  /boot  → $EFI_PART   mount only (no format)"
        echo "─────────────────────────────────────────────────────────────"
        read -rp "Proceed? Type 'yes' to confirm: " CONFIRM
        [[ "$CONFIRM" == "yes" ]] || { echo "Aborted."; exit 1; }

        # ── Format ───────────────────────────────────────────────────
        if $FORMAT_ROOT; then
            echo "Formatting root partition as $ROOT_FS..."
            mkfs."$ROOT_FS" -F "$ROOT_PART"
        fi

        if $FORMAT_EFI; then
            echo "Formatting EFI partition as FAT32..."
            mkfs.fat -F32 "$EFI_PART"
        fi
        ;;

    *)
        echo "Invalid option. Aborted."
        exit 1
        ;;
esac

# ------------------------------------------------------------------
# Mounting (common to both modes)
# ------------------------------------------------------------------
echo ""
echo "Mounting filesystems..."

mount "$ROOT_PART" /mnt
mkdir -p /mnt/boot
mount "$EFI_PART" /mnt/boot

echo ""
echo "Pre-install complete. Layout:"
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT "$ROOT_PART" "$EFI_PART" 2>/dev/null || true
