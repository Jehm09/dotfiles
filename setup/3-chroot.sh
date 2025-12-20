#!/usr/bin/env bash
# Script ejecutado DENTRO del sistema instalado (arch-chroot)
# Se encarga de dejar el sistema usable: locale, users, bootloader, servicios

set -Eeuo pipefail

# =============================
# Configuración global
# =============================

TIMEZONE="America/Bogota"
LOCALE="en_US.UTF-8"
KEYMAP="us"

# =============================
# Zona horaria y reloj
# =============================

echo "⏱️ Configurando zona horaria: $TIMEZONE"

ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime

# Sincroniza el reloj hardware con el sistema
hwclock --systohc

# =============================
# Locales
# =============================

echo "🌐 Configurando locale: $LOCALE"

# Descomenta el locale requerido (sin borrar otros)
sed -i "s/^#\($LOCALE UTF-8\)/\1/" /etc/locale.gen

# Genera los locales
locale-gen

# Define el idioma por defecto del sistema
echo "LANG=$LOCALE" > /etc/locale.conf

# =============================
# Teclado en consola
# =============================

echo "⌨️ Configurando teclado: $KEYMAP"
echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf

# =============================
# Hostname y hosts
# =============================

echo "💻 Configurando hostname"
read -rp "Ingresa hostname: " HOSTNAME

echo "$HOSTNAME" > /etc/hostname

cat > /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
EOF

# =============================
# Usuario root
# =============================

echo "🔑 Configurando contraseña de root"
passwd

# =============================
# Usuario principal
# =============================

echo "👤 Creando usuario principal"
read -rp "Ingresa nombre de usuario: " USERNAME

useradd -m -G wheel -s /bin/bash "$USERNAME"
passwd "$USERNAME"

# Habilita sudo para el grupo wheel
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# =============================
# Servicios
# =============================

echo "🚀 Habilitando servicios esenciales"

# Red
systemctl enable NetworkManager

# =============================
# ZRAM Swap
# =============================

echo "⚡ Instalando y configurando zram"

pacman -S --noconfirm zram-generator

cat > /etc/systemd/zram-generator.conf <<EOF
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
swap-priority = 100
EOF

# Recarga systemd y activa zram
systemctl daemon-reload
systemctl start systemd-zram-setup@zram0.service

# =============================
# Fin del chroot
# =============================

echo
echo "✅ Chroot configurado correctamente"
echo "➡️  Puedes salir del chroot, desmontar /mnt y reiniciar"
