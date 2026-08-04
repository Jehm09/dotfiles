#!/usr/bin/env bash
# Region screenshot -> clipboard AND file.  Port of the Hyprland Ctrl+Print bind.
#
# Saves to $(xdg-user-dir PICTURES)/Screenshots/Screenshot_<date>.png, the same
# location the Hyprland bind used.
#
# Usage: screenshot-save.sh [--clipboard-only]

set -euo pipefail

APP_NAME="Captura"
source "$(dirname "$(readlink -f "$0")")/lib.sh"

clipboard_only=false
[[ "${1:-}" == "--clipboard-only" ]] && clipboard_only=true

# Clipboard-only: let Spectacle put the image on the clipboard itself with -c.
# No temp file and no wl-copy — Spectacle hands the image straight to Klipper,
# which is what owns the clipboard on Plasma. Note that -c is ignored when -o is
# given ("copy screenshot image to clipboard, unless -o is also used"), which is
# why this path must NOT go through capture_region.
if [[ "$clipboard_only" == true ]]; then
    require spectacle
    spectacle -r -b -n -k -c >/dev/null 2>&1 || true
    notify-send -a "$APP_NAME" "Captura copiada al portapapeles"
    exit 0
fi

# File mode: a file is required, so -o wins and the clipboard copy has to be
# done separately. Images cannot go through Klipper's setClipboardContents
# (it takes a QString), so wl-copy is the only option here.
require wl-copy

dir="$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Pictures")/Screenshots"
mkdir -p "$dir"
target="$dir/Screenshot_$(date '+%Y-%m-%d_%H.%M.%S').png"

capture_region "$target" || exit 0   # selección cancelada

wl-copy --type image/png < "$target"
notify-send -a "$APP_NAME" "Captura guardada" "$target"
