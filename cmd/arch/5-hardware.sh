#!/usr/bin/env bash
# Hardware configuration: CPU microcode, Wi-Fi, Bluetooth, PipeWire, GPU drivers.
# Run inside arch-chroot as part of the install sequence.
#
# Called by cmd/arch/run.sh via arch-chroot.

set -Eeuo pipefail

DOTFILES="/root/dotfiles_src"
source "$DOTFILES/lib/utils.sh"
source "$DOTFILES/lib/detect.sh"

PACKAGES_DIR="$DOTFILES/packages/hardware"

[[ -d "$PACKAGES_DIR" ]] || {
    error "Hardware package directory not found: $PACKAGES_DIR"
    exit 1
}

# Install packages from a .conf file, printing the section label
install_hw() {
    local label="$1"
    local file="$2"
    [[ -f "$file" ]] || { warn "$file not found, skipping $label"; return; }
    mapfile -t pkgs < <(parse_packages "$file")
    [[ ${#pkgs[@]} -eq 0 ]] && return
    info "Installing $label (${#pkgs[@]} packages)..."
    pacman -S --needed --noconfirm "${pkgs[@]}"
}

# ------------------------------------------------------------------
# CPU microcode
# ------------------------------------------------------------------
step "CPU microcode"
detect_cpu
info "CPU: $CPU_BRAND ($CPU_VENDOR)"

case "$CPU_BRAND" in
    Intel) install_hw "Intel CPU microcode" "$PACKAGES_DIR/cpu-intel.conf" ;;
    AMD)   install_hw "AMD CPU microcode"   "$PACKAGES_DIR/cpu-amd.conf"   ;;
    *)     warn "Unknown CPU vendor ($CPU_VENDOR), skipping microcode"      ;;
esac

# ------------------------------------------------------------------
# Common hardware support (Wi-Fi, Bluetooth, PipeWire, zram)
# ------------------------------------------------------------------
step "Common hardware"
install_hw "hardware support" "$PACKAGES_DIR/common.conf"

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
if is_laptop; then
    step "Laptop power management"
    install_hw "laptop power management" "$PACKAGES_DIR/laptop.conf"
    systemctl enable tlp
else
    info "No battery detected (desktop) - skipping TLP"
fi

# ------------------------------------------------------------------
# GPU drivers
# ------------------------------------------------------------------
step "GPU drivers"
detect_gpu
info "GPU detection: Intel=$HAS_INTEL_GPU AMD=$HAS_AMD_GPU NVIDIA=$HAS_NVIDIA_GPU"

$HAS_INTEL_GPU  && install_hw "Intel GPU drivers"  "$PACKAGES_DIR/gpu-intel.conf"
$HAS_AMD_GPU    && install_hw "AMD GPU drivers"    "$PACKAGES_DIR/gpu-amd.conf"

if $HAS_NVIDIA_GPU; then
    install_hw "NVIDIA proprietary drivers" "$PACKAGES_DIR/gpu-nvidia.conf"

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

    info "Rebuilding initramfs for NVIDIA modules..."
    mkinitcpio -P
fi

echo ""
success "Hardware configuration complete."
