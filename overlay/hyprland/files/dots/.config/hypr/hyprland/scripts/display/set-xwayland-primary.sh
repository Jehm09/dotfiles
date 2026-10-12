#!/usr/bin/env bash
# Marca como primario de XWayland el primer monitor de display.order que esté
# conectado (el mismo criterio que el greeter). Steam y los juegos X11 abren en
# el primario, y se resuelve por EDID porque el conector (DP-N) cambia entre arranques.

set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../env.sh"
[[ -f "$CONFIG_JSON" ]] || { echo "[display/set-xwayland-primary] falta $CONFIG_JSON" >&2; exit 1; }

primary_output() {
    jq -r --argjson live "$(live_monitors_json)" "$_JQ_MONITOR_LIB"'
        [ ordered($live)[] | live_of(.; $live) | select(. != null) ][0].name // empty' "$CONFIG_JSON"
}

# Tras un hotplug XWayland tarda un instante en publicar la salida nueva.
for _ in 1 2 3 4 5; do
    output="$(primary_output)"
    [[ -n "$output" ]] && xrandr --output "$output" --primary 2>/dev/null && exit 0
    sleep 0.5
done
echo "[display/set-xwayland-primary] no se pudo marcar '${output:-?}' como primario" >&2
exit 1
