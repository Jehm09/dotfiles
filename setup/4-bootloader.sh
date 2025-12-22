#!/usr/bin/env bash
# Configura GRUB como bootloader UEFI con soporte dual boot

set -Eeuo pipefail

echo "🚀 Configurando bootloader: GRUB (UEFI)"

# =============================
# Checks básicos
# =============================

[[ -d /sys/firmware/efi ]] || {
  echo "❌ Sistema no iniciado en UEFI"
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
# Instalar paquetes
# =============================

echo "📦 Instalando GRUB y herramientas necesarias"

pacman -S --noconfirm \
  grub \
  efibootmgr \
  os-prober \
  ntfs-3g

# =============================
# Habilitar os-prober
# =============================

echo "🔍 Habilitando os-prober"

sed -i 's/^#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub

# =============================
# Instalar GRUB en la ESP
# =============================

echo "💾 Instalando GRUB en modo UEFI"

grub-install \
  --target=x86_64-efi \
  --efi-directory=/boot \
  --bootloader-id=GRUB \
  --recheck

# =============================
# Generar configuración
# =============================

echo "🧾 Generando grub.cfg"
os-prober || true
sleep 2

grub-mkconfig -o /boot/grub/grub.cfg

# =============================
# Final
# =============================

echo
echo "✅ GRUB instalado correctamente"
echo "👉 Windows será detectado automáticamente si existe"
