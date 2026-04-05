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

    # ── MODE 2: delete selected partitions → create EFI + root in freed space ──
    2)
        mapfile -t PARTS < <(lsblk -n -o NAME,TYPE | awk '$2=="part"{print $1}')

        if [[ ${#PARTS[@]} -eq 0 ]]; then
            echo "ERROR: No partitions found."
            exit 1
        fi

        # Show numbered list with size/fstype info
        echo ""
        echo "Available partitions:"
        echo ""
        for i in "${!PARTS[@]}"; do
            info=$(lsblk -n -o SIZE,FSTYPE,LABEL "/dev/${PARTS[$i]}" 2>/dev/null | head -1)
            printf "  %2d) %s  %s\n" "$((i+1))" "${PARTS[$i]}" "$info"
        done
        echo ""

        # Multi-select: user types numbers separated by spaces
        read -rp "Numbers of partitions to DELETE (space-separated, e.g. 3 4): " -a SELECTIONS

        [[ ${#SELECTIONS[@]} -gt 0 ]] || { echo "No partitions selected. Aborted."; exit 1; }

        # Resolve selections → device names
        declare -a TO_DELETE=()
        for sel in "${SELECTIONS[@]}"; do
            idx=$((sel - 1))
            if [[ $idx -lt 0 || $idx -ge ${#PARTS[@]} ]]; then
                echo "ERROR: '$sel' is not a valid number."
                exit 1
            fi
            TO_DELETE+=("${PARTS[$idx]}")
        done

        # Validate all partitions are on the same disk
        declare -a PARENT_DISKS=()
        for part in "${TO_DELETE[@]}"; do
            disk=$(lsblk -n -o PKNAME "/dev/$part" 2>/dev/null)
            [[ -n "$disk" ]] || { echo "ERROR: could not determine parent disk of $part."; exit 1; }
            PARENT_DISKS+=("$disk")
        done

        mapfile -t UNIQUE_DISKS < <(printf '%s\n' "${PARENT_DISKS[@]}" | sort -u)
        if [[ ${#UNIQUE_DISKS[@]} -ne 1 ]]; then
            echo "ERROR: selected partitions span multiple disks (${UNIQUE_DISKS[*]})."
            echo "       All partitions to delete must be on the same disk."
            exit 1
        fi

        TARGET="/dev/${UNIQUE_DISKS[0]}"

        # Show deletion plan
        echo ""
        echo "── Plan ─────────────────────────────────────────────────────"
        echo "  Disk: $TARGET"
        echo "  Partitions to DELETE:"
        for part in "${TO_DELETE[@]}"; do
            info=$(lsblk -n -o SIZE,FSTYPE,LABEL "/dev/$part" 2>/dev/null | head -1)
            echo "    /dev/$part  $info"
        done
        echo "  Then create:"
        echo "    EFI   ${EFI_SIZE} FAT32"
        echo "    root  remaining  $ROOT_FS"
        echo "─────────────────────────────────────────────────────────────"
        read -rp "Type 'yes' to confirm: " CONFIRM
        [[ "$CONFIRM" == "yes" ]] || { echo "Aborted."; exit 1; }

        # Delete selected partitions
        for part in "${TO_DELETE[@]}"; do
            part_num=$(cat "/sys/class/block/$part/partition" 2>/dev/null) \
                || part_num=$(echo "$part" | grep -o '[0-9]*$')
            echo "Deleting /dev/$part (partition $part_num on $TARGET)..."
            parted -s "$TARGET" rm "$part_num"
        done

        partprobe "$TARGET"
        sleep 1

        # Show disk state after deletion
        echo ""
        echo "Disk layout after deletion:"
        parted -s "$TARGET" unit MiB print free
        echo ""

        # Find start of the largest free-space region
        read -r FREE_START FREE_END < <(
            parted -s "$TARGET" unit MiB print free \
            | awk '/Free Space/ {
                size = $2 - $1
                if (size > best) { best = size; start = $1; end = $2 }
              }
              END { gsub(/MiB/, "", start); gsub(/MiB/, "", end); print start, end }' \
            | sed 's/MiB//g'
        )

        [[ -n "$FREE_START" && -n "$FREE_END" ]] || {
            echo "ERROR: could not find free space on $TARGET after deletion."
            exit 1
        }

        EFI_END=$(echo "$FREE_START + 1024" | bc)

        echo "Creating EFI partition (${FREE_START}MiB → ${EFI_END}MiB)..."
        parted -s "$TARGET" mkpart ESP fat32 "${FREE_START}MiB" "${EFI_END}MiB"

        echo "Creating root partition (${EFI_END}MiB → ${FREE_END}MiB)..."
        parted -s "$TARGET" mkpart primary "$ROOT_FS" "${EFI_END}MiB" "${FREE_END}MiB"

        partprobe "$TARGET"
        sleep 2

        # Identify the two new partitions (highest start sectors = just created)
        mapfile -t NEW_PARTS < <(
            lsblk -n -o NAME,TYPE "$TARGET" | awk '$2=="part"{print $1}' \
            | while read -r p; do
                start=$(cat "/sys/class/block/$p/start" 2>/dev/null || echo 0)
                echo "$start $p"
              done \
            | sort -n | tail -2 | awk '{print $2}'
        )

        [[ ${#NEW_PARTS[@]} -eq 2 ]] || {
            echo "ERROR: could not identify the new partitions."
            lsblk "$TARGET"
            exit 1
        }

        EFI_PART="/dev/${NEW_PARTS[0]}"
        ROOT_PART="/dev/${NEW_PARTS[1]}"

        echo "Formatting EFI partition ($EFI_PART) as FAT32..."
        mkfs.fat -F32 "$EFI_PART"

        # Set ESP flag — need partition number
        efi_num=$(cat "/sys/class/block/${NEW_PARTS[0]}/partition" 2>/dev/null) \
            || efi_num=$(echo "${NEW_PARTS[0]}" | grep -o '[0-9]*$')
        parted -s "$TARGET" set "$efi_num" esp on

        echo "Formatting root partition ($ROOT_PART) as $ROOT_FS..."
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
echo ""
echo "Mounting filesystems..."

mount "$ROOT_PART" /mnt
mkdir -p /mnt/boot
mount "$EFI_PART" /mnt/boot

echo ""
echo "Pre-install complete. Layout:"
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT "$ROOT_PART" "$EFI_PART" 2>/dev/null || true
