#!/usr/bin/env bash
# Aplica la configuración de monitores leyendo
# el config.json de quickshell (gestionado por quickshell settings).
#
# Hace dos cosas:
#   1) Dispatchea `hl.monitor({...})` vía hyprctl para los monitores que difieren
#      del estado actual (idempotente — sólo lo que cambió).
#   2) Regenera ~/.config/hypr/monitors.lua con `hl.monitor({...})` literales,
#      para que el próximo `hyprctl reload` aplique los modos directamente
#      durante el parseo del config (sin pasar por modo "preferred" default —
#      esa era la causa del parpadeo de DP-2).
#
# Sólo se invoca desde watch.sh cuando el JSON cambia. monitors.lua NO debe
# llamarlo: ese archivo guarda la última config y se evalúa solo.

set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../env.sh"
MONITORS_LUA="${HYPR_DIR}/monitors.lua"
[[ -f "$CONFIG_JSON" ]] || { echo "[display/apply-monitors] falta $CONFIG_JSON" >&2; exit 1; }

# 1) Regenerar monitors.lua atómicamente con hl.monitor({...}) literales.
{
    echo "-- Auto-generado por hyprland/scripts/display/apply-monitors.sh"
    echo "-- Fuente: ~/.config/settings/quickshell/config.json"
    echo "-- NO EDITAR A MANO: cualquier cambio se sobreescribe al guardar display."
    echo ""
    jq -r '.display.monitors[] |
        if .enabled == false then
            "hl.monitor({ output = \"\(.name)\", disabled = true })"
        else
            "hl.monitor({ output = \"\(.name)\", mode = \"\(.width)x\(.height)@\(.refreshRate)\", position = \"\(.x)x\(.y)\", scale = \(.scale // 1) })"
        end
    ' "$CONFIG_JSON"
} > "${MONITORS_LUA}.tmp" && mv "${MONITORS_LUA}.tmp" "$MONITORS_LUA"

# 2) Dispatch a Hyprland — sólo lo que difiera del estado actual.
CURRENT=$(hyprctl -j monitors all 2>/dev/null || echo '[]')

# diff_gt a b eps -> retorna 0 (true) si |a-b| > eps.
diff_gt() {
    awk -v a="$1" -v b="$2" -v eps="$3" 'BEGIN { d=(a-b); if (d<0) d=-d; exit (d>eps ? 0 : 1) }'
}

# needs_change -> retorna 0 (true) si hay que aplicar dispatch.
needs_change() {
    local name="$1" w="$2" h="$3" hz="$4" x="$5" y="$6" scale="$7" want_enabled="$8"
    local mon
    mon=$(echo "$CURRENT" | jq -c --arg n "$name" '.[] | select(.name == $n)')
    [[ -z "$mon" || "$mon" == "null" ]] && return 0

    local cur_disabled
    cur_disabled=$(echo "$mon" | jq -r '.disabled // false')

    if [[ "$want_enabled" == "false" ]]; then
        [[ "$cur_disabled" == "true" ]] && return 1
        return 0
    fi
    [[ "$cur_disabled" == "true" ]] && return 0

    local cur_w cur_h cur_hz cur_x cur_y cur_scale
    cur_w=$(echo "$mon" | jq -r '.width')
    cur_h=$(echo "$mon" | jq -r '.height')
    cur_hz=$(echo "$mon" | jq -r '.refreshRate')
    cur_x=$(echo "$mon" | jq -r '.x')
    cur_y=$(echo "$mon" | jq -r '.y')
    cur_scale=$(echo "$mon" | jq -r '.scale')

    [[ "$cur_w" != "$w" || "$cur_h" != "$h" ]] && return 0
    [[ "$cur_x" != "$x" || "$cur_y" != "$y" ]] && return 0
    diff_gt "$cur_hz" "$hz" 0.1 && return 0      # 0.1 Hz tolerance
    diff_gt "$cur_scale" "$scale" 0.001 && return 0
    return 1
}

jq -r '.display.monitors[] | "\(.name)|\(.width)|\(.height)|\(.refreshRate)|\(.x)|\(.y)|\(.scale // 1)|\(if .enabled == false then "false" else "true" end)"' \
    "$CONFIG_JSON" | while IFS='|' read -r name w h hz x y scale enabled; do
    [[ -z "$name" ]] && continue
    needs_change "$name" "$w" "$h" "$hz" "$x" "$y" "$scale" "$enabled" || continue

    if [[ "$enabled" == "false" ]]; then
        hyprctl eval "hl.monitor({output = \"$name\", disabled = true})" >/dev/null 2>&1
    else
        scale_f=$(awk -v s="$scale" 'BEGIN { printf "%.6f", s }')
        # disabled = false explícito para reactivar monitores previamente disabled.
        hyprctl eval \
            "hl.monitor({output = \"$name\", mode = \"${w}x${h}@${hz}\", position = \"${x}x${y}\", scale = $scale_f, disabled = false})" \
            >/dev/null 2>&1
    fi
done
