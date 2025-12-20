#!/usr/bin/env bash
# Configura entorno gráfico Wayland con Hyprland + seatd

set -Eeuo pipefail

echo "🖥️ Instalando entorno gráfico (Hyprland + Wayland)"

pacman -S --noconfirm \
  hyprland \
  seatd \
  kitty \
  dolphin \
  dunst \
  grim \
  slurp \
  wofi \
  qt5-wayland \
  qt6-wayland \
  xdg-desktop-portal-hyprland \
  xdg-desktop-portal \
  sddm

# -----------------------------
# Seatd
# -----------------------------
echo "🔐 Configurando seatd"

# Habilita el servicio
systemctl enable seatd

# Añade TODOS los usuarios reales (UID >= 1000) al grupo seat
echo "👥 Añadiendo usuarios al grupo seat"

awk -F: '$3 >= 1000 && $1 != "nobody" { print $1 }' /etc/passwd | while read -r user; do
  usermod -aG seat "$user"
  echo "  ✔ $user agregado al grupo seat"
done

# -----------------------------
# SDDM
# -----------------------------
echo "🪟 Habilitando SDDM"
systemctl enable sddm

# -----------------------------
# NVIDIA + Wayland fixes
# -----------------------------
if lspci | grep -qi nvidia; then
  echo "🟢 Aplicando variables NVIDIA para Wayland"

  cat > /etc/environment <<EOF
GBM_BACKEND=nvidia-drm
__GLX_VENDOR_LIBRARY_NAME=nvidia
WLR_NO_HARDWARE_CURSORS=1
EOF
fi

# -----------------------------
# Portales
# -----------------------------
echo "🧩 Configurando xdg-desktop-portal"

# El servicio se inicia por usuario al login
# No fallar si aún no hay sesión
systemctl --global enable xdg-desktop-portal || true

echo "✅ Desktop configurado correctamente"
