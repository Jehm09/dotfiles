#!/usr/bin/env bash
# Hardware detection utilities sourced by setup scripts.
# Do not execute directly.
#
# After calling the detect_* functions, the following variables are set:
#   CPU_VENDOR    - "GenuineIntel" | "AuthenticAMD" | "Unknown"
#   CPU_BRAND     - "Intel" | "AMD" | "Unknown"
#   HAS_INTEL_GPU - true | false
#   HAS_AMD_GPU   - true | false
#   HAS_NVIDIA_GPU- true | false

# ------------------------------------------------------------------
# CPU detection
# ------------------------------------------------------------------
detect_cpu() {
    CPU_VENDOR=$(awk -F: '/Vendor ID/ {gsub(/ /,"",$2); print $2}' /proc/cpuinfo | head -n1)
    case "$CPU_VENDOR" in
        GenuineIntel) CPU_BRAND="Intel" ;;
        AuthenticAMD)  CPU_BRAND="AMD"   ;;
        *)             CPU_BRAND="Unknown"; CPU_VENDOR="Unknown" ;;
    esac
}

# ------------------------------------------------------------------
# GPU detection
# ------------------------------------------------------------------
detect_gpu() {
    local gpu_info
    gpu_info=$(lspci -nn 2>/dev/null | grep -E "VGA|3D" || true)

    HAS_INTEL_GPU=false
    HAS_AMD_GPU=false
    HAS_NVIDIA_GPU=false

    echo "$gpu_info" | grep -qi "intel"          && HAS_INTEL_GPU=true
    echo "$gpu_info" | grep -qi "amd\|radeon"    && HAS_AMD_GPU=true
    echo "$gpu_info" | grep -qi "nvidia"         && HAS_NVIDIA_GPU=true
}

# ------------------------------------------------------------------
# Laptop detection (battery present)
# ------------------------------------------------------------------
is_laptop() {
    ls /sys/class/power_supply/BAT* &>/dev/null 2>&1
}

# ------------------------------------------------------------------
# Print a summary of detected hardware
# ------------------------------------------------------------------
print_hardware_summary() {
    detect_cpu
    detect_gpu
    echo "  CPU : $CPU_BRAND ($CPU_VENDOR)"
    echo -n "  GPU :"
    $HAS_INTEL_GPU  && echo -n " Intel"
    $HAS_AMD_GPU    && echo -n " AMD"
    $HAS_NVIDIA_GPU && echo -n " NVIDIA"
    echo ""
    is_laptop && echo "  Type: Laptop" || echo "  Type: Desktop"
}
