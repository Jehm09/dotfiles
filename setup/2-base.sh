#!/usr/bin/env bash
# Script encargado de instalar el sistema base de Arch Linux
# Se ejecuta desde el entorno live, con las particiones ya montadas en /mnt

set -Eeuo pipefail

# =============================
# Checks iniciales
# =============================

# Verifica que /mnt esté montado
# Si no lo está, pacstrap fallará
mountpoint -q /mnt || {
  echo "❌ /mnt no está montado. Ejecuta primero el preinstall."
  exit 1
}

# =============================
# Instalación del sistema base
# =============================

echo "📦 Instalando sistema base y kernel linux-zen"

# pacstrap instala los paquetes base dentro de /mnt
# base            → sistema mínimo
# linux-zen       → kernel optimizado para desktop
# linux-firmware  → firmware necesario para hardware común
# vim, nano       → editor básico
# sudo            → escalamiento de privilegios
# networkmanager  → gestión de red
pacstrap /mnt \
  base \
  linux-zen \
  linux-firmware \
  linux-zen-headers \
  vim \
  nano \
  sudo \
  networkmanager

# =============================
# Generación de fstab
# =============================

echo "🧾 Generando fstab"

# -U : usa UUIDs (más seguro que nombres de dispositivos)
# >> : append para no sobrescribir si se regenera
genfstab -U /mnt >> /mnt/etc/fstab

# =============================
# Preparación para chroot
# =============================

echo "📂 Copiando scripts de instalación al nuevo sistema"

# Copiamos la carpeta setup completa al nuevo sistema
# para poder ejecutar 3-chroot.sh desde dentro del chroot
cp -r setup /mnt/root/

# =============================
# Fin del base install
# =============================

echo
echo "✅ Base instalada correctamente"
echo "➡️  Próximo paso: arch-chroot /mnt y ejecutar 3-chroot.sh"
