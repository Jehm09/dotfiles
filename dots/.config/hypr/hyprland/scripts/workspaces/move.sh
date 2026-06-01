#!/usr/bin/env bash
# Navegación / movimiento de workspaces con grupos POR MONITOR.
# Lee la configuración desde el config.json de quickshell settings
# (display.order, display.monitors, display.workspaces).
#
# Uso:
#   move.sh --action focus|move|movefollow [opciones]
#
# Selectores de destino:
#   --key N            1..(GROUP_SIZE*NUM_MONITORS). Mapea tecla numérica a
#                      (monitor, slot) según el orden de display.order.
#   --slot S           Slot 1..GROUP_SIZE dentro del grupo actual del monitor
#                      destino (por defecto: monitor enfocado).
#   --slot-dir ±1      Slot relativo dentro del grupo del monitor enfocado,
#                      con wrap-around.
#   --group-dir ±1     Cambia de grupo en el monitor enfocado. Respeta
#                      display.workspaces.cycle (true = no crea grupos nuevos).
#   --monitor-idx N    Forza el índice de monitor destino (0-based).

set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../env.sh"

if [[ ! -f "$CONFIG_JSON" ]]; then
    echo "[workspaces/move] falta $CONFIG_JSON" >&2
    exit 1
fi

GROUP_SIZE=$(jq -r '.display.workspaces.perMonitor // 5' "$CONFIG_JSON")
CYCLE_ONLY=$(jq -r '.display.workspaces.cycle // false' "$CONFIG_JSON")

mapfile -t WORKSPACES_MONITORS < <(enabled_monitors_ordered)

NUM_MONITORS=${#WORKSPACES_MONITORS[@]}
if (( NUM_MONITORS == 0 )); then
    echo "[workspaces/move] no hay monitores enabled en $CONFIG_JSON" >&2
    exit 1
fi
BLOCK=$(( GROUP_SIZE * NUM_MONITORS ))

action="focus"
key=""
slot=""
slot_dir=""
group_dir=""
target_monitor_idx=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --action) action="$2"; shift 2 ;;
        --key) key="$2"; shift 2 ;;
        --slot) slot="$2"; shift 2 ;;
        --slot-dir) slot_dir="$2"; shift 2 ;;
        --group-dir) group_dir="$2"; shift 2 ;;
        --monitor-idx) target_monitor_idx="$2"; shift 2 ;;
        -h|--help) sed -n '2,/^set/p' "$0" | head -n -1; exit 0 ;;
        *) echo "[workspaces/move] arg desconocido: $1" >&2; exit 1 ;;
    esac
done

ws_id_of()         { echo $(( $2 * BLOCK + $1 * GROUP_SIZE + $3 )); }
monitor_idx_of_ws(){ echo $(( (($1 - 1) / GROUP_SIZE) % NUM_MONITORS )); }
group_of_ws()      { echo $(( ($1 - 1) / BLOCK )); }
slot_of_ws()       { echo $(( (($1 - 1) % GROUP_SIZE) + 1 )); }

find_monitor_idx() {
    local target="$1" i
    for i in "${!WORKSPACES_MONITORS[@]}"; do
        if [[ "${WORKSPACES_MONITORS[$i]}" == "$target" ]]; then
            echo "$i"
            return 0
        fi
    done
    return 1
}

ensure_group_persistent() {
    local mon_idx="$1" grp="$2" mon s ws
    mon="${WORKSPACES_MONITORS[$mon_idx]}"
    for s in $(seq 1 "$GROUP_SIZE"); do
        ws=$(ws_id_of "$mon_idx" "$grp" "$s")
        hyprctl dispatch "hl.workspace_rule({workspace = \"${ws}\", monitor = \"${mon}\", persistent = true})" >/dev/null 2>&1
    done
}

focused_monitor=$(hyprctl -j activeworkspace 2>/dev/null | jq -r '.monitor // empty' 2>/dev/null || echo "")
focused_idx=""
if [[ -n "$focused_monitor" ]]; then
    focused_idx=$(find_monitor_idx "$focused_monitor" || echo "")
fi

if [[ -n "$key" ]]; then
    if (( key < 1 || key > BLOCK )); then
        exit 0
    fi
    target_monitor_idx=$(( (key - 1) / GROUP_SIZE ))
    slot=$(( ((key - 1) % GROUP_SIZE) + 1 ))
fi

if [[ -z "$target_monitor_idx" ]]; then
    target_monitor_idx="${focused_idx:-0}"
fi
if (( target_monitor_idx < 0 || target_monitor_idx >= NUM_MONITORS )); then
    exit 0
fi

target_monitor="${WORKSPACES_MONITORS[$target_monitor_idx]}"
target_active_ws=$(hyprctl -j monitors 2>/dev/null \
    | jq -r --arg name "$target_monitor" '.[] | select(.name==$name) | .activeWorkspace.id // empty' \
    2>/dev/null || echo "")

if [[ -n "$target_active_ws" && "$target_active_ws" -gt 0 ]] \
   && [[ "$(monitor_idx_of_ws "$target_active_ws")" -eq "$target_monitor_idx" ]]; then
    current_group=$(group_of_ws "$target_active_ws")
    current_slot=$(slot_of_ws "$target_active_ws")
else
    current_group=0
    current_slot=1
fi

target_group=$current_group
target_slot=""

if [[ -n "$slot" ]]; then
    target_slot=$slot
fi

if [[ -n "$slot_dir" ]]; then
    target_slot=$(( ((current_slot - 1 + slot_dir + GROUP_SIZE) % GROUP_SIZE) + 1 ))
fi

if [[ -n "$group_dir" ]]; then
    if [[ "$CYCLE_ONLY" == "true" ]]; then
        : # no cambia de grupo
    else
        new_group=$(( current_group + group_dir ))
        if (( new_group < 0 )); then new_group=0; fi
        target_group=$new_group
    fi
    [[ -z "$target_slot" ]] && target_slot=$current_slot
fi

[[ -z "$target_slot" ]] && target_slot=$current_slot

target_ws=$(ws_id_of "$target_monitor_idx" "$target_group" "$target_slot")

if (( target_group != current_group )); then
    ensure_group_persistent "$target_monitor_idx" "$target_group"
else
    hyprctl dispatch "hl.workspace_rule({workspace = \"${target_ws}\", monitor = \"${target_monitor}\", persistent = true})" >/dev/null 2>&1
fi

case "$action" in
    focus)
        hyprctl dispatch "hl.dsp.focus({workspace = \"${target_ws}\"})" >/dev/null
        ;;
    move)
        hyprctl dispatch "hl.dsp.window.move({workspace = \"${target_ws}\", follow = false})" >/dev/null
        ;;
    movefollow)
        hyprctl dispatch "hl.dsp.window.move({workspace = \"${target_ws}\", follow = true})" >/dev/null
        ;;
    *) echo "[workspaces/move] acción desconocida: $action" >&2; exit 1 ;;
esac
