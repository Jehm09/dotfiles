#!/usr/bin/env bash
# Usamos bash explícitamente desde el entorno live de Arch

# -E  : hereda traps en funciones
# -e  : termina el script si un comando falla
# -u  : error si se usa una variable no definida
# -o pipefail : falla si falla cualquier comando en un pipe
set -Eeuo pipefail

# =============================
# Configuración global
# =============================

# Mapa de teclado (se puede sobreescribir desde fuera)
# Ej: KEYMAP=la-latin1 ./1-preinstall.sh
KEYMAP="${KEYMAP:-us}"

EFI_SIZE="1024MiB"
ROOT_FS="ext4"
LOG_FILE="preinstall.log"

# Redirige stdout y stderr al log y a la consola al mismo tiempo
# Muy útil para debug si algo falla
exec > >(tee "$LOG_FILE") 2>&1

# =============================
# Checks básicos
# =============================

echo "🔍 Ejecutando checks iniciales..."

# Verifica que la arquitectura sea x86_64
# Arch Linux solo soporta oficialmente esta arquitectura
[[ "$(uname -m)" == "x86_64" ]] || {
  echo "❌ Solo x86_64 soportado"
  exit 1
}

# Verifica que el sistema esté booteado en modo UEFI
# Si no existe este directorio, estamos en modo BIOS/Legacy
[[ -d /sys/firmware/efi ]] || {
  echo "❌ Este script solo funciona en sistemas UEFI"
  exit 1
}

# Verifica conectividad a internet
# Necesaria para instalar paquetes en los siguientes pasos
ping -c 1 archlinux.org >/dev/null || {
  echo "❌ No hay conexión a internet"
  exit 1
}

# =============================
# Configuración inicial
# =============================

# Configura el mapa de teclado
# Importante para evitar errores al escribir contraseñas
echo "⌨️  Configurando teclado: $KEYMAP"
loadkeys "$KEYMAP"

# Habilita sincronización NTP
# Asegura que el reloj del sistema sea correcto
echo "⏱️  Sincronizando reloj"
timedatectl set-ntp true

# =============================
# Selección de disco
# =============================

# Muestra los discos físicos disponibles
# -d : solo discos, no particiones
echo
echo "📀 Discos disponibles:"
lsblk -d -o NAME,SIZE,MODEL
echo

# Guarda los nombres de los discos en un array
mapfile -t DISKS < <(lsblk -d -n -o NAME)

# Menú interactivo para seleccionar el disco destino
PS3="Selecciona el disco donde instalar Arch: "
select DISK in "${DISKS[@]}"; do
  [[ -n "$DISK" ]] && break
done

# Ruta completa del disco seleccionado
TARGET="/dev/$DISK"

# Advertencia clara antes de borrar todo
echo
echo "⚠️  ADVERTENCIA"
echo "Todo el contenido de $TARGET será ELIMINADO"
read -rp "¿Estás seguro? (y/N): " CONFIRM

# Cancela si el usuario no confirma explícitamente
[[ "$CONFIRM" == "y" ]] || {
  echo "❌ Instalación cancelada"
  exit 1
}

# =============================
# Particionado del disco
# =============================

# Elimina firmas de sistemas de archivos y particiones previas
# Evita conflictos con instalaciones anteriores
echo "🧹 Eliminando firmas previas"
wipefs -af "$TARGET"

# Crea una nueva tabla de particiones GPT
# Requerida para sistemas UEFI
echo "📐 Creando tabla GPT"
parted -s "$TARGET" mklabel gpt

# Crea la partición EFI (ESP)
# - FAT32
# - Donde el firmware UEFI busca los bootloaders
echo "📂 Creando partición EFI (${EFI_SIZE})"
parted -s "$TARGET" mkpart ESP fat32 1MiB "$EFI_SIZE"
# Activa el Efi system a la particion
parted -s "$TARGET" set 1 esp on

# Crea la partición root con el resto del disco
echo "📂 Creando partición root (resto del disco)"
parted -s "$TARGET" mkpart primary "$ROOT_FS" "$EFI_SIZE" 100%

# Fuerza al kernel a recargar la tabla de particiones
# Evita errores de "device not found"
echo "🔄 Sincronizando tabla de particiones"
partprobe "$TARGET"
sleep 2

# =============================
# Resolución de nombres de particiones
# =============================

# Algunos discos (NVMe, MMC) requieren 'p1', 'p2'
# Ej:
#   /dev/sda1
#   /dev/nvme0n1p1
if [[ "$TARGET" =~ [0-9]$ ]]; then
  EFI_PART="${TARGET}p1"
  ROOT_PART="${TARGET}p2"
else
  EFI_PART="${TARGET}1"
  ROOT_PART="${TARGET}2"
fi

# =============================
# Formateo de particiones
# =============================

# Formatea la partición EFI en FAT32
echo "🧼 Formateando EFI (FAT32)"
mkfs.fat -F32 "$EFI_PART"

# Formatea la partición root con el filesystem elegido
echo "🧼 Formateando root ($ROOT_FS)"
mkfs."$ROOT_FS" -F "$ROOT_PART"

# =============================
# Montaje del sistema
# =============================

# Monta la partición root en /mnt
# /mnt es el punto estándar durante la instalación de Arch
echo "📌 Montando sistema de archivos"
mount "$ROOT_PART" /mnt

# Crea el punto de montaje para EFI
mkdir -p /mnt/boot

# Monta la partición EFI
mount "$EFI_PART" /mnt/boot

# =============================
# Fin del preinstall
# =============================

echo
echo "✅ Preinstall completado correctamente"
echo "📄 Log guardado en $LOG_FILE"
