#!/usr/bin/env bash
# Region OCR -> clipboard.  Port of the Hyprland Super+Shift+X bind
# (grim -g "$(slurp)" | tesseract | wl-copy) onto Spectacle for KWin.
#
# Spectacle 6.6+ also has an "Extract Text" button in its viewer; this is the
# one-shot, bind-to-a-key version.

set -euo pipefail

APP_NAME="OCR"
source "$(dirname "$(readlink -f "$0")")/lib.sh"

require tesseract

shot="$(mktemp -t ocr-XXXXXX.png)"
trap 'rm -f "$shot"' EXIT

capture_region "$shot" || exit 0   # selección cancelada

# All installed languages joined with "+". "osd" is orientation/script detection,
# not a language — passing it to -l makes tesseract fail.
langs="$(tesseract --list-langs 2>/dev/null | awk 'NR>1 && $1 != "osd" {print $1}' | paste -sd+ -)"

text="$(tesseract "$shot" stdout -l "${langs:-eng}" 2>/dev/null || true)"

if [[ -z "${text//[[:space:]]/}" ]]; then
    notify-send -a "$APP_NAME" "OCR" "No se reconoció ningún texto"
    exit 0
fi

printf '%s' "$text" | copy_text
notify-send -a "$APP_NAME" "Texto copiado al portapapeles" "$(printf '%s' "$text" | head -c 200)"
