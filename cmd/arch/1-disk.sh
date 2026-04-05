#!/usr/bin/env bash
# Disk partitioning, formatting, and mounting.
# Run from the Arch ISO live environment as root.
#
# Override keyboard layout:  KEYMAP=la-latin1 ./setup arch

set -Eeuo pipefail

KEYMAP="${KEYMAP:-us}"
EFI_SIZE="1024MiB"
EFI_SIZE_MIB="${EFI_SIZE%MiB}"   # numeric only, for arithmetic
ROOT_FS="ext4"

# Partition variables — set by whichever mode runs
EFI_PART=""
ROOT_PART=""
TARGET=""

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
# Helpers
# ------------------------------------------------------------------

# Pick a disk interactively; sets global TARGET
pick_disk() {
    local prompt="${1:-Select disk}"
    local disks
    mapfile -t disks < <(lsblk -ldn -o NAME)
    PS3="$prompt: "
    local chosen
    select chosen in "${disks[@]}"; do
        [[ -n "$chosen" ]] && break
    done
    TARGET="/dev/$chosen"
}

# partprobe + short settle wait
partprobe_wait() {
    partprobe "$TARGET"
    sleep 2
}

# Format EFI as FAT32 (+ set ESP flag) and root as ROOT_FS
# Requires: EFI_PART, ROOT_PART, TARGET set
format_partitions() {
    echo "Formatting EFI partition ($EFI_PART) as FAT32..."
    mkfs.fat -F32 "$EFI_PART"

    local efi_num
    efi_num=$(cat "/sys/class/block/${EFI_PART##/dev/}/partition" 2>/dev/null) \
        || efi_num=$(echo "${EFI_PART##/dev/}" | grep -o '[0-9]*$')
    parted -s "$TARGET" set "$efi_num" esp on

    echo "Formatting root partition ($ROOT_PART) as $ROOT_FS..."
    mkfs."$ROOT_FS" -F "$ROOT_PART"
}

# ------------------------------------------------------------------
# Install mode selection
# ------------------------------------------------------------------
echo "Install mode:"
echo "  1) Whole disk        — erase everything and partition from scratch"
echo "  2) Existing partitions — delete chosen partitions and use freed space (dual-boot)"
echo ""
read -rp "Select mode [1/2]: " MODE

case "$MODE" in
    # ── MODE 1: whole disk ────────────────────────────────────────────
    1)
        pick_disk "Select the disk to install Arch Linux on"

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

        partprobe_wait

        # NVMe/MMC use 'p' prefix: /dev/nvme0n1p1 vs /dev/sda1
        if [[ "$TARGET" =~ [0-9]$ ]]; then
            EFI_PART="${TARGET}p1"
            ROOT_PART="${TARGET}p2"
        else
            EFI_PART="${TARGET}1"
            ROOT_PART="${TARGET}2"
        fi

        format_partitions
        ;;

    # ── MODE 2: delete selected partitions → use freed space ─────────
    2)
        mapfile -t PARTS < <(lsblk -ln -o NAME,TYPE | awk '$2=="part"{print $1}')

        echo ""
        echo "Available partitions (Enter nothing to skip deletion and use existing free space):"
        echo ""
        for i in "${!PARTS[@]}"; do
            local_disk=$(lsblk -ln -o PKNAME "/dev/${PARTS[$i]}" 2>/dev/null)
            info=$(lsblk -ln -o SIZE,FSTYPE,LABEL "/dev/${PARTS[$i]}" 2>/dev/null | head -1)
            printf "  %2d) %-12s disk: %-8s %s\n" "$((i+1))" "${PARTS[$i]}" "$local_disk" "$info"
        done
        echo ""

        read -rp "Numbers of partitions to DELETE (space-separated, Enter to skip): " -ra SELECTIONS

        declare -a TO_DELETE=()

        if [[ ${#SELECTIONS[@]} -gt 0 ]]; then
            for sel in "${SELECTIONS[@]}"; do
                idx=$((sel - 1))
                if [[ $idx -lt 0 || $idx -ge ${#PARTS[@]} ]]; then
                    echo "ERROR: '$sel' is not a valid number."
                    exit 1
                fi
                TO_DELETE+=("${PARTS[$idx]}")
            done

            # Validate all selected partitions are on the same disk
            declare -a PARENT_DISKS=()
            for part in "${TO_DELETE[@]}"; do
                disk=$(lsblk -ln -o PKNAME "/dev/$part" 2>/dev/null)
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
        else
            echo "No partitions selected — using existing free space."
            pick_disk "Select disk that has the free space"
        fi

        # Show plan and confirm
        echo ""
        echo "── Plan ─────────────────────────────────────────────────────"
        echo "  Disk: $TARGET"
        if [[ ${#TO_DELETE[@]} -gt 0 ]]; then
            echo "  Partitions to DELETE:"
            for part in "${TO_DELETE[@]}"; do
                info=$(lsblk -ln -o SIZE,FSTYPE,LABEL "/dev/$part" 2>/dev/null | head -1)
                echo "    /dev/$part  $info"
            done
        else
            echo "  No partitions deleted — using existing free space"
        fi
        echo "  Then create in largest free space:"
        echo "    EFI   ${EFI_SIZE} FAT32"
        echo "    root  remaining  $ROOT_FS"
        echo "─────────────────────────────────────────────────────────────"
        read -rp "Type 'yes' to confirm: " CONFIRM
        [[ "$CONFIRM" == "yes" ]] || { echo "Aborted."; exit 1; }

        # Delete selected partitions (if any)
        for part in "${TO_DELETE[@]}"; do
            part_num=$(cat "/sys/class/block/$part/partition" 2>/dev/null) \
                || part_num=$(echo "$part" | grep -o '[0-9]*$')
            echo "Deleting /dev/$part (partition $part_num on $TARGET)..."
            parted -s "$TARGET" rm "$part_num"
        done

        if [[ ${#TO_DELETE[@]} -gt 0 ]]; then
            partprobe_wait
        fi

        echo ""
        echo "Disk layout on $TARGET:"
        parted -s "$TARGET" unit MiB print free
        echo ""

        # Find largest free-space region; strip MiB suffix and round to integers
        read -r FREE_START FREE_END < <(
            parted -s "$TARGET" unit MiB print free \
            | awk '/Free Space/ {
                gsub(/MiB/, "", $1); gsub(/MiB/, "", $2)
                size = $2 - $1
                if (size > best) { best = size; start = $1; end = $2 }
              }
              END { printf "%d %d\n", int(start + 0.999), int(end) }'
        )

        [[ -n "$FREE_START" && -n "$FREE_END" ]] || {
            echo "ERROR: could not find free space on $TARGET."
            exit 1
        }

        # Parted rejects values < 1 MiB
        [[ $FREE_START -lt 1 ]] && FREE_START=1

        EFI_END=$((FREE_START + EFI_SIZE_MIB))

        # Snapshot partitions BEFORE creating — diff after to find the new ones
        mapfile -t PARTS_BEFORE < <(lsblk -ln -o NAME,TYPE "$TARGET" | awk '$2=="part"{print $1}')

        echo "Creating EFI partition (${FREE_START}MiB → ${EFI_END}MiB)..."
        parted -s "$TARGET" mkpart ESP fat32 "${FREE_START}MiB" "${EFI_END}MiB"

        echo "Creating root partition (${EFI_END}MiB → ${FREE_END}MiB)..."
        parted -s "$TARGET" mkpart primary "$ROOT_FS" "${EFI_END}MiB" "${FREE_END}MiB"

        partprobe_wait

        # New partitions = after minus before, sorted by start sector (EFI first)
        mapfile -t NEW_PARTS < <(
            lsblk -ln -o NAME,TYPE "$TARGET" | awk '$2=="part"{print $1}' \
            | while read -r p; do
                for old in "${PARTS_BEFORE[@]}"; do
                    [[ "$p" == "$old" ]] && continue 2
                done
                start=$(cat "/sys/class/block/$p/start" 2>/dev/null || echo 0)
                echo "$start $p"
              done \
            | sort -n | awk '{print $2}'
        )

        [[ ${#NEW_PARTS[@]} -eq 2 ]] || {
            echo "ERROR: expected 2 new partitions, found ${#NEW_PARTS[@]}."
            lsblk "$TARGET"
            exit 1
        }

        EFI_PART="/dev/${NEW_PARTS[0]}"
        ROOT_PART="/dev/${NEW_PARTS[1]}"

        echo "New partitions: EFI=$EFI_PART  root=$ROOT_PART"
        format_partitions
        ;;

    *)
        echo "Invalid option. Aborted."
        exit 1
        ;;
esac

# ------------------------------------------------------------------
# Review partition table before mounting
# ------------------------------------------------------------------
echo ""
echo "════════════════════════════════════════════════════════════"
echo "  Partition table — review before mounting"
echo "════════════════════════════════════════════════════════════"
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT
echo ""
echo "  EFI  will mount at → /mnt/boot   ($EFI_PART)"
echo "  Root will mount at → /mnt         ($ROOT_PART)"
echo "════════════════════════════════════════════════════════════"
echo ""
read -rp "Looks good? Type 'yes' to mount and continue, anything else to abort: " REVIEW
[[ "$REVIEW" == "yes" ]] || { echo "Aborted. Nothing has been mounted."; exit 1; }

# ------------------------------------------------------------------
# Mounting
# ------------------------------------------------------------------
echo ""
echo "Mounting filesystems..."
mount "$ROOT_PART" /mnt
mkdir -p /mnt/boot
mount "$EFI_PART" /mnt/boot

echo ""
echo "Pre-install complete. Layout:"
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT "$ROOT_PART" "$EFI_PART" 2>/dev/null || true
