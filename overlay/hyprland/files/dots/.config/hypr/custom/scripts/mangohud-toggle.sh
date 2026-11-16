#!/usr/bin/env bash
# Muestra/oculta el overlay de MangoHud en todos los juegos abiertos a la vez: alterna la línea
# `no_display` de su config, que cada juego vigila con inotify y recarga al cambiar.
set -euo pipefail

conf="${MANGOHUD_CONFIGFILE:-${XDG_CONFIG_HOME:-$HOME/.config}/MangoHud/MangoHud.conf}"
[[ -f $conf ]] || { notify-send -a MangoHud "MangoHud" "No existe $conf"; exit 1; }

flag='^[[:space:]]*no_display[[:space:]]*$'
content="$(<"$conf")"

# Reescritura en el mismo inodo (`>`): sed -i o mv crean un archivo nuevo y el watch de inotify
# de los juegos ya abiertos se quedaría mirando el viejo.
if grep -q "$flag" <<<"$content"; then
    printf '%s\n' "$(grep -v "$flag" <<<"$content" || true)" >"$conf"
else
    printf '%s\nno_display\n' "$content" >"$conf"
fi
