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
# Regla del monitor único: si al aplicar queda una sola pantalla encendida, se
# ignora su posición guardada y se la manda a 0,0. Una pantalla única lejos del
# origen deja ventanas y juegos en coordenadas que ya no corresponden a nada
# visible. El JSON conserva la posición real: vuelve sola al encender la segunda.
#
# Los monitores se identifican por `desc:<descripción EDID>`, no por nombre de
# conector: ver el comentario en ../env.sh. Así el .lua generado sigue siendo
# válido aunque el kernel renombre los conectores (actualización de driver) o
# muevas el cable a otro puerto, sin tener que regenerarlo.
#
# Sólo se invoca desde watch.sh cuando el JSON cambia. monitors.lua NO debe
# llamarlo: ese archivo guarda la última config y se evalúa solo.

set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../env.sh"
MONITORS_LUA="${HYPR_DIR}/monitors.lua"
[[ -f "$CONFIG_JSON" ]] || { echo "[display/apply-monitors] falta $CONFIG_JSON" >&2; exit 1; }

CURRENT=$(live_monitors_json)

# Un registro por monitor: selector estable, nombre de conector actual (para
# diffear contra hyprctl) y los ajustes guardados.
#
# Cuentan como encendidos sólo los habilitados que además están conectados
# (presentes en hyprctl): uno habilitado pero desenchufado no evita que el que
# queda sea el único, y por lo tanto vaya a 0,0.
#
# Ningún campo puede quedar vacío: el tab es whitespace para IFS, así que dos
# tabs seguidos colapsarían en uno y correrían todas las columnas siguientes.
records() {
    jq -r --argjson live "$CURRENT" "$_JQ_MONITOR_LIB"'
        (.display.monitors // []) as $mons
        | ([ $mons[]
             | select((.enabled != false) and (live_of(.; $live) != null)) ] | length) as $on_count
        | $mons[]
        | (.enabled != false) as $on
        | ($on and $on_count == 1 and (live_of(.; $live) != null)) as $solo
        | [ (selector_of(.; $live) | if . == "" then "-" else . end),
            (name_of(.; $live) | if . == "" then "-" else . end),
            (.width // 0), (.height // 0), (.refreshRate // 0),
            (if $solo then 0 else (.x // 0) end),
            (if $solo then 0 else (.y // 0) end),
            (.scale // 1),
            (if $on then "true" else "false" end) ]
        | @tsv' "$CONFIG_JSON"
}

# Una sola pasada de jq: el mismo set de registros alimenta el .lua y el dispatch.
mapfile -t RECORDS < <(records)

# Nombres de conector que Hyprland tiene encendidos ahora mismo.
LIVE_ON=$(echo "$CURRENT" | jq -r '.[] | select((.disabled // false) == false) | .name')
live_enabled() { grep -qxF "$1" <<<"$LIVE_ON"; }

# 1) Regenerar monitors.lua atómicamente con hl.monitor({...}) literales.
{
    echo "-- Auto-generado por hyprland/scripts/display/apply-monitors.sh"
    echo "-- Fuente: ~/.config/settings/quickshell/config.json"
    echo "-- NO EDITAR A MANO: cualquier cambio se sobreescribe al guardar display."
    echo ""
    for rec in "${RECORDS[@]}"; do
        IFS=$'\t' read -r sel name w h hz x y scale enabled <<<"$rec"
        [[ -z "$sel" ]] && continue
        if [[ "$enabled" == "false" ]]; then
            echo "hl.monitor({ output = \"${sel}\", disabled = true })"
        else
            echo "hl.monitor({ output = \"${sel}\", mode = \"${w}x${h}@${hz}\", position = \"${x}x${y}\", scale = ${scale} })"
        fi
    done
} > "${MONITORS_LUA}.tmp" && mv "${MONITORS_LUA}.tmp" "$MONITORS_LUA"

# El greeter sigue el mismo orden: el primero es su monitor.
"$(dirname "${BASH_SOURCE[0]}")/sync-greeter-output.sh"

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

dispatch() {
    local sel="$1" w="$2" h="$3" hz="$4" x="$5" y="$6" scale="$7" enabled="$8"
    if [[ "$enabled" == "false" ]]; then
        hyprctl eval "hl.monitor({output = \"$sel\", disabled = true})" >/dev/null 2>&1
        return
    fi
    local scale_f
    scale_f=$(awk -v s="$scale" 'BEGIN { printf "%.6f", s }')
    # disabled = false explícito para reactivar monitores previamente disabled.
    hyprctl eval \
        "hl.monitor({output = \"$sel\", mode = \"${w}x${h}@${hz}\", position = \"${x}x${y}\", scale = $scale_f, disabled = false})" \
        >/dev/null 2>&1
}

# 2) Dispatch a Hyprland — sólo lo que difiera del estado actual, en tres
# pasadas: apagar, reubicar los que ya estaban encendidos y recién entonces
# encender los nuevos. Así, al salir del modo monitor único, el que estaba en
# 0,0 se corre antes de que otro ocupe el origen y nunca quedan superpuestos.
apply_phase() {
    local phase="$1" rec sel name w h hz x y scale enabled
    for rec in "${RECORDS[@]}"; do
        IFS=$'\t' read -r sel name w h hz x y scale enabled <<<"$rec"
        [[ -z "$sel" ]] && continue
        case "$phase" in
            disable) [[ "$enabled" == "false" ]] || continue ;;
            move)    { [[ "$enabled" == "false" ]] || ! live_enabled "$name"; } && continue ;;
            enable)  { [[ "$enabled" == "false" ]] || live_enabled "$name"; } && continue ;;
        esac
        needs_change "$name" "$w" "$h" "$hz" "$x" "$y" "$scale" "$enabled" || continue
        dispatch "$sel" "$w" "$h" "$hz" "$x" "$y" "$scale" "$enabled"
    done
}

apply_phase disable
apply_phase move
apply_phase enable
