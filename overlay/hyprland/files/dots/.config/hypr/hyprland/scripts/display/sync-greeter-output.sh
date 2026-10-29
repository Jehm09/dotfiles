#!/usr/bin/env bash
# Copia display.order de config.json (sólo los habilitados) a
# /etc/greetd/greeter-output: el primero es el monitor del greeter y el resto el
# fallback si no está conectado. El greeter corre como `greeter` y no puede leer
# $HOME, por eso la copia.
#
# Sólo escribe si el archivo es tuyo: 'setup greeter apply' te lo cede cuando el
# greeter sigue el orden, y lo deja de root cuando hay un GREETER_OUTPUT fijo.

set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../env.sh"
GREETER_OUTPUT_FILE=/etc/greetd/greeter-output

[[ -w "$GREETER_OUTPUT_FILE" && -f "$CONFIG_JSON" ]] || exit 0

descs=$(jq -r '
    (.display.monitors // []) as $mons
    | (.display.order // [])[]
    | . as $d
    | select(any($mons[]; .desc == $d and .enabled != false))' "$CONFIG_JSON") || exit 0
[[ -n "$descs" ]] || exit 0

{
    echo "# Monitors the greeter prefers, most wanted first."
    echo "# Synced from display.order in ~/.config/settings/quickshell/config.json"
    echo "# by hypr/hyprland/scripts/display/sync-greeter-output.sh — do not edit."
    echo "$descs"
} > "$GREETER_OUTPUT_FILE"
