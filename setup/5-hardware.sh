#!/usr/bin/env bash
# ----------------------------------------
# Configuración de hardware base del sistema
# Se ejecuta dentro del arch-chroot
# ----------------------------------------

set -Eeuo pipefail

echo "🔧 Iniciando configuración de hardware"

# =============================
# CPU Microcode
# =============================
# Detecta el fabricante del CPU para instalar el microcode correcto
# Mejora estabilidad, seguridad y fixes de CPU

echo "🧠 Detectando CPU"

CPU_VENDOR=$(awk -F: '/Vendor ID/ {gsub(/ /,"",$2); print $2}' /proc/cpuinfo | head -n1)

case "$CPU_VENDOR" in
  GenuineIntel)
    echo "➡️ CPU Intel detectado"
    pacman -S --noconfirm intel-ucode
    ;;
  AuthenticAMD)
    echo "➡️ CPU AMD detectado"
    pacman -S --noconfirm amd-ucode
    ;;
  *)
    echo "⚠️ Fabricante de CPU desconocido, omitiendo microcode"
    ;;
esac

# =============================
# Red inalámbrica (Wi-Fi)
# =============================
# NetworkManager ya está instalado
# Estos paquetes aseguran compatibilidad amplia

echo "📡 Configurando Wi-Fi"

pacman -S --noconfirm \
  iwd \
  wireless_tools \
  wpa_supplicant

# =============================
# Bluetooth (BlueZ)
# =============================
# BlueZ es el stack Bluetooth oficial en Linux
# PipeWire manejará el audio Bluetooth

echo "🟦 Configurando Bluetooth"

pacman -S --noconfirm \
  bluez \
  bluez-utils

systemctl enable bluetooth

# =============================
# Audio moderno (PipeWire)
# =============================
# Reemplaza PulseAudio y JACK
# Compatible con Wayland / Hyprland

echo "🔊 Configurando audio con PipeWire"

pacman -S --noconfirm \
  pipewire \
  pipewire-alsa \
  pipewire-pulse \
  pipewire-jack \
  wireplumber

# =============================
# Power management (solo laptops)
# =============================
# Detecta batería para decidir si instalar TLP

if ls /sys/class/power_supply/BAT* &>/dev/null; then
  echo "🔋 Laptop detectada, instalando TLP"
  pacman -S --noconfirm tlp
  systemctl enable tlp
else
  echo "🖥️ Desktop detectado, omitiendo TLP"
fi

# =============================
# GPU Drivers
# =============================
# Detecta GPU y instala los drivers correctos
# No instala entorno gráfico ni compositor

echo "🎮 Detectando GPU"

GPU_INFO=$(lspci -nn | grep -E "VGA|3D")

echo "$GPU_INFO"

# Intel GPU
if echo "$GPU_INFO" | grep -qi intel; then
  echo "➡️ GPU Intel detectada"
  pacman -S --noconfirm \
    mesa \
    vulkan-intel \
    intel-media-driver
fi

# AMD GPU
if echo "$GPU_INFO" | grep -qi amd; then
  echo "➡️ GPU AMD detectada"
  pacman -S --noconfirm \
    mesa \
    vulkan-radeon \
    libva-mesa-driver
fi

# # NVIDIA GPU (nouveau por defecto)
# if echo "$GPU_INFO" | grep -qi nvidia; then
#   echo "➡️ GPU NVIDIA detectada"
#   pacman -S --noconfirm \
#     mesa \
#     nouveau \
#     vulkan-nouveau
# fi

# =============================
# NVIDIA Proprietary Driver
# =============================
# Solo se instala si se detecta GPU NVIDIA
# Preparado para Wayland + Hyprland
if echo "$GPU_INFO" | grep -qi nvidia; then
  echo "🟢 Configurando NVIDIA propietario"

  # Paquetes DKMS en lugar de nvidia fijo
  pacman -S --noconfirm \
    nvidia-dkms \
    nvidia-utils \
    nvidia-settings

  echo "⚙️ Configurando NVIDIA DRM"

  cat > /etc/modprobe.d/nvidia.conf <<EOF
options nvidia-drm modeset=1
EOF

  echo "⛔ Bloqueando nouveau"

  cat > /etc/modprobe.d/blacklist-nouveau.conf <<EOF
blacklist nouveau
options nouveau modeset=0
EOF

  echo "🧱 Configurando initramfs"

  sed -i 's/^MODULES=.*/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia-drm)/' /etc/mkinitcpio.conf

  mkinitcpio -P

else
  echo "ℹ️ NVIDIA no detectada, omitiendo driver propietario"
fi


# =============================
# Final
# =============================

echo
echo "✅ Configuración de hardware completada correctamente"
