#!/usr/bin/env bash
# Hardware configuration: CPU microcode, Wi-Fi, Bluetooth, PipeWire, GPU drivers.
# Run inside arch-chroot as part of the install sequence.
#
# Package lists: /root/packages/hardware/ (copied there by 2-base.sh)

set -Eeuo pipefail

PACKAGES_DIR="/root/packages/hardware"

[[ -d "$PACKAGES_DIR" ]] || {
    echo "ERROR: Hardware package directory not found: $PACKAGES_DIR"
    exit 1
}

# Parse a package file: strip comments and blank lines, return one package name per line
parse_packages() {
    grep -v '^\s*#' "$1" \
        | grep -v '^\s*$' \
        | awk '{print $1}' \
        | grep -v '^$'
}

# Install packages from a file, printing the section label
install_from_file() {
    local label="$1"
    local file="$2"
    [[ -f "$file" ]] || { echo "WARNING: $file not found, skipping $label"; return; }
    mapfile -t pkgs < <(parse_packages "$file")
    [[ ${#pkgs[@]} -eq 0 ]] && return
    echo "Installing $label (${#pkgs[@]} packages)..."
    pacman -S --needed --noconfirm "${pkgs[@]}"
}

# ------------------------------------------------------------------
# CPU microcode
# ------------------------------------------------------------------
echo "Detecting CPU vendor..."
CPU_VENDOR=$(awk -F: '/Vendor ID/ {gsub(/ /,"",$2); print $2}' /proc/cpuinfo | head -n1)

case "$CPU_VENDOR" in
    GenuineIntel)
        echo "  Intel CPU detected"
        install_from_file "Intel CPU microcode" "$PACKAGES_DIR/cpu-intel.txt"
        ;;
    AuthenticAMD)
        echo "  AMD CPU detected"
        install_from_file "AMD CPU microcode" "$PACKAGES_DIR/cpu-amd.txt"
        ;;
    *)
        echo "  Unknown CPU vendor ($CPU_VENDOR), skipping microcode"
        ;;
esac

# ------------------------------------------------------------------
# Common hardware support (Wi-Fi, Bluetooth, PipeWire, zram)
# ------------------------------------------------------------------
install_from_file "hardware support" "$PACKAGES_DIR/common.txt"

# Enable Bluetooth service
systemctl enable bluetooth

# Configure zram swap (half of RAM, zstd compression)
cat > /etc/systemd/zram-generator.conf <<'EOF'
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
swap-priority = 100
EOF

# ------------------------------------------------------------------
# Power management (laptop only)
# ------------------------------------------------------------------
if ls /sys/class/power_supply/BAT* &>/dev/null 2>&1; then
    echo "Battery detected (laptop) - installing power management..."
    install_from_file "laptop power management" "$PACKAGES_DIR/laptop.txt"
    systemctl enable tlp
else
    echo "No battery detected (desktop) - skipping TLP"
fi

# ------------------------------------------------------------------
# GPU drivers
# ------------------------------------------------------------------
echo "Detecting GPU..."
GPU_INFO=$(lspci -nn 2>/dev/null | grep -E "VGA|3D" || true)
echo "  $GPU_INFO"

if echo "$GPU_INFO" | grep -qi intel; then
    echo "  Intel GPU detected"
    install_from_file "Intel GPU drivers" "$PACKAGES_DIR/gpu-intel.txt"
fi

if echo "$GPU_INFO" | grep -qi "amd\|radeon"; then
    echo "  AMD GPU detected"
    install_from_file "AMD GPU drivers" "$PACKAGES_DIR/gpu-amd.txt"
fi

if echo "$GPU_INFO" | grep -qi nvidia; then
    echo "  NVIDIA GPU detected"
    install_from_file "NVIDIA proprietary drivers" "$PACKAGES_DIR/gpu-nvidia.txt"

    # Enable NVIDIA DRM kernel mode setting (required for Wayland)
    cat > /etc/modprobe.d/nvidia.conf <<'EOF'
options nvidia-drm modeset=1
options nvidia NVreg_PreserveVideoMemoryAllocations=1
EOF

    # Blacklist the open-source nouveau driver to avoid conflicts
    cat > /etc/modprobe.d/blacklist-nouveau.conf <<'EOF'
blacklist nouveau
options nouveau modeset=0
EOF

    # Add NVIDIA modules to initramfs for early KMS
    sed -i 's/^MODULES=(\(.*\))/MODULES=(\1 nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' \
        /etc/mkinitcpio.conf
    # Handle the case where MODULES=() is empty
    sed -i 's/^MODULES=( nvidia/MODULES=(nvidia/' /etc/mkinitcpio.conf

    echo "Rebuilding initramfs for NVIDIA modules..."
    mkinitcpio -P
fi

echo ""
echo "Hardware configuration complete."
