#!/usr/bin/env bash
set -Eeuo pipefail

echo "🚀 Instalador Arch Linux"

echo "🌍 Optimizando mirrors (reflector)"

pacman -Sy --noconfirm reflector

reflector \
  --country Colombia,United_States \
  --age 12 \
  --protocol https \
  --sort rate \
  --save /etc/pacman.d/mirrorlist

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "➡️ Paso 1: Preinstall"
"$SCRIPT_DIR/setup/1-preinstall.sh"

echo "➡️ Paso 2: Base system"
"$SCRIPT_DIR/setup/2-base.sh"

echo "➡️ Entrando al chroot"
arch-chroot /mnt /bin/bash <<EOF
cd /root/setup
chmod +x *.sh
./3-chroot.sh
./4-bootloader.sh
./5-hardware.sh
./6-desktop.sh
EOF

echo "✅ Instalación completada"
echo "👉 Ya puedes reiniciar"
