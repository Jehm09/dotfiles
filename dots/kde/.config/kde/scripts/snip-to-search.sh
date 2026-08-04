#!/usr/bin/env bash
# Region -> Google Lens reverse image search.  Port of the Hyprland Super+Shift+A
# bind (hypr/hyprland/scripts/snip_to_search.sh) onto Spectacle for KWin.
#
# Uploads the crop to uguu.se (files expire after a few hours) and opens Lens
# with that URL.

set -euo pipefail

APP_NAME="Buscar imagen"
source "$(dirname "$(readlink -f "$0")")/lib.sh"

require curl jq xdg-open

shot="$(mktemp -t lens-XXXXXX.png)"
trap 'rm -f "$shot"' EXIT

capture_region "$shot" || exit 0   # selección cancelada

link="$(curl -sf -F "files[]=@$shot" 'https://uguu.se/upload' | jq -r '.files[0].url // empty')"
[[ -n "$link" ]] || die "No se pudo subir la imagen a uguu.se"

xdg-open "https://lens.google.com/uploadbyurl?url=${link}"
