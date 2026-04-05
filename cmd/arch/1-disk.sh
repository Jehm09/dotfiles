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
SWAP_PART=""
HOME_PART=""
FORMAT_HOME=false

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
        echo "Assign a role to each partition. Partitions listed:"
        lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT | grep -v "^loop"
        echo ""

        # ── Root (required) ───────────────────────────────────────────
        echo "── ROOT  (required, will be formatted as $ROOT_FS) ──"
        ROOT_PART=$(pick_partition "Root partition")
        [[ -b "$ROOT_PART" ]] || { echo "ERROR: invalid root partition."; exit 1; }

        # ── EFI (required) ────────────────────────────────────────────
        echo ""
        echo "── EFI / ESP  (required, will NOT be reformatted) ──"
        echo "   Tip: on a Windows disk this is usually the first small FAT32 partition."
        EFI_PART=$(pick_partition "EFI partition")
        [[ -b "$EFI_PART" ]] || { echo "ERROR: invalid EFI partition."; exit 1; }

        # ── Swap (optional) ───────────────────────────────────────────
        echo ""
        echo "── SWAP  (optional — skip if you prefer a swapfile later) ──"
        SWAP_PART=$(pick_partition "Swap partition" yes)

        # ── Home (optional) ───────────────────────────────────────────
        echo ""
        echo "── HOME  (optional — skip to use a single root partition) ──"
        HOME_PART=$(pick_partition "Home partition" yes)

        if [[ -n "$HOME_PART" ]]; then
            echo ""
            read -rp "Format $HOME_PART as ext4? Choosing 'no' keeps existing data. [y/N]: " fmt_home
            [[ "$fmt_home" =~ ^[Yy]$ ]] && FORMAT_HOME=true
        fi

        # ── Sanity: no duplicate assignments ─────────────────────────
        declare -A _seen
        for _p in "$ROOT_PART" "$EFI_PART" "${SWAP_PART:-}" "${HOME_PART:-}"; do
            [[ -z "$_p" ]] && continue
            if [[ -n "${_seen[$_p]+set}" ]]; then
                echo "ERROR: $p assigned to more than one role."
                exit 1
            fi
            _seen[$_p]=1
        done

        # ── Confirm plan ──────────────────────────────────────────────
        echo ""
        echo "── Plan ─────────────────────────────────────────────────────"
        echo "  Root  → $ROOT_PART   (format as $ROOT_FS)"
        echo "  EFI   → $EFI_PART   (mount only, no format)"
        [[ -n "$SWAP_PART" ]] && echo "  Swap  → $SWAP_PART   (mkswap + swapon)"
        if [[ -n "$HOME_PART" ]]; then
            $FORMAT_HOME \
                && echo "  Home  → $HOME_PART   (format as ext4)" \
                || echo "  Home  → $HOME_PART   (mount, keep existing data)"
        fi
        echo "─────────────────────────────────────────────────────────────"
        read -rp "Proceed? Type 'yes' to confirm: " CONFIRM
        [[ "$CONFIRM" == "yes" ]] || { echo "Aborted."; exit 1; }

        # ── Format ───────────────────────────────────────────────────
        echo "Formatting root partition as $ROOT_FS..."
        mkfs."$ROOT_FS" -F "$ROOT_PART"

        if [[ -n "$HOME_PART" ]] && $FORMAT_HOME; then
            echo "Formatting home partition as ext4..."
            mkfs.ext4 -F "$HOME_PART"
        fi

        if [[ -n "$SWAP_PART" ]]; then
            echo "Setting up swap..."
            mkswap "$SWAP_PART"
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

if [[ -n "$HOME_PART" ]]; then
    mkdir -p /mnt/home
    mount "$HOME_PART" /mnt/home
fi

if [[ -n "$SWAP_PART" ]]; then
    swapon "$SWAP_PART"
fi

echo ""
echo "Pre-install complete. Layout:"
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT "$ROOT_PART" "$EFI_PART" ${SWAP_PART:+"$SWAP_PART"} ${HOME_PART:+"$HOME_PART"} 2>/dev/null || true
