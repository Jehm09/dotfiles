#!/usr/bin/env bash
set -Eeuo pipefail

chmod +x setup/*.sh

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

echo "🧾 Configuración inicial"

read -rp "Hostname: " HOSTNAME
read -rp "Usuario principal: " USERNAME

echo "Contraseña para $USERNAME y root:"
read -rsp "Password: " PASSWORD
echo
read -rsp "Confirmar password: " PASSWORD_CONFIRM
echo

[[ "$PASSWORD" == "$PASSWORD_CONFIRM" ]] || {
  echo "❌ Las contraseñas no coinciden"
  exit 1
}

CONFIG_FILE="/mnt/root/setup/install.conf"

mkdir -p /mnt/root/setup

cat > "$CONFIG_FILE" <<EOF
HOSTNAME="$HOSTNAME"
USERNAME="$USERNAME"
PASSWORD="$PASSWORD"
TIMEZONE="America/Bogota"
LOCALE="en_US.UTF-8"
KEYMAP="us"
EOF

echo "➡️ Entrando al chroot"
arch-chroot /mnt /bin/bash <<EOF
set -e
cd /root/setup
chmod +x *.sh
./3-chroot.sh
./4-bootloader.sh
./5-hardware.sh
./6-desktop.sh
rm -f install.conf
EOF

echo "✅ Instalación completada"
echo "👉 Ya puedes reiniciar"
