#!/usr/bin/env bash
# Configura systemd-boot como gestor de arranque (UEFI)
# - Menú visible 10 segundos
# - Arch Linux
# - Windows si existe

set -Eeuo pipefail

echo "🚀 Configurando bootloader: systemd-boot"

# =============================
# Checks básicos
# =============================

[[ -d /sys/firmware/efi ]] || {
  echo "❌ El sistema no está en modo UEFI"
  exit 1
}

[[ -d /boot ]] || {
  echo "❌ /boot no existe"
  exit 1
}

BOOT_FS=$(findmnt -n -o FSTYPE /boot)
[[ "$BOOT_FS" == "vfat" ]] || {
  echo "❌ /boot no es una partición EFI (vfat)"
  exit 1
}

# =============================
# Instalar systemd-boot
# =============================

echo "💾 Instalando systemd-boot"
bootctl install

# =============================
# loader.conf
# =============================

echo "⚙️ Configurando loader.conf"

mkdir -p /boot/loader

cat > /boot/loader/loader.conf <<EOF
default arch
timeout 10
editor 0
EOF

# =============================
# Entrada de Arch Linux
# =============================

echo "🐧 Creando entrada de Arch Linux"

ROOT_UUID=$(findmnt / -no UUID)

mkdir -p /boot/loader/entries

cat > /boot/loader/entries/arch.conf <<EOF
title   Arch Linux
linux   /vmlinuz-linux-zen
initrd  /initramfs-linux-zen.img
options root=UUID=$ROOT_UUID rw
EOF

# =============================
# Detección de Windows (opcional)
# =============================

WINDOWS_EFI="/boot/EFI/Microsoft/Boot/bootmgfw.efi"

if [[ -f "$WINDOWS_EFI" ]]; then
  echo "🪟 Windows detectado, creando entrada"

  cat > /boot/loader/entries/windows.conf <<EOF
title   Windows Boot Manager
efi     /EFI/Microsoft/Boot/bootmgfw.efi
EOF
else
  echo "ℹ️ Configurando windows por defecto"

    cat > /boot/loader/entries/windows.conf <<EOF
title   Windows Boot Manager
efi     /shellx64.efi
EOF
fi

# =============================
# Final
# =============================

echo
echo "✅ systemd-boot configurado correctamente"
echo "👉 Menú visible durante 10 segundos"
