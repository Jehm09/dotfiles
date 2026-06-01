#!/usr/bin/env bash
# Aplica las reglas de workspaces (asignación a monitor + persistencia)
# leyendo el config.json de quickshell settings.
#
# Hace tres cosas:
#   1) Regenera ~/.config/hypr/workspaces.lua con `hl.workspace_rule({...})`
#      literales, para que el próximo `hyprctl reload` cargue las reglas
#      directamente durante el parseo (sin depender de un dispatch tardío).
#   2) Dispatchea las reglas vía hyprctl para que tomen efecto ya.
#   3) Limpia reglas huérfanas (workspaces que estaban persistent y ya no
#      están en el set actual — por reducir perMonitor, deshabilitar un
#      monitor o reordenar). Mueve sus ventanas al ws 1.
#
# Con --reset-focus, además lleva cada monitor a su primer slot y deja el
# foco final en el monitor que estaba enfocado originalmente.
#
# Sólo se invoca desde watch.sh cuando el JSON cambia. workspaces.lua NO debe
# llamarlo: ese archivo guarda la última config y se evalúa solo.

set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../env.sh"
WORKSPACES_LUA="${HYPR_DIR}/workspaces.lua"

RESET_FOCUS=false
for arg in "$@"; do
    case "$arg" in
        --reset-focus) RESET_FOCUS=true ;;
    esac
done

[[ -f "$CONFIG_JSON" ]] || { echo "[display/apply-workspaces] falta $CONFIG_JSON" >&2; exit 1; }

GROUP_SIZE=$(jq -r '.display.workspaces.perMonitor // 5' "$CONFIG_JSON")
mapfile -t MONITORS < <(enabled_monitors_ordered)

NUM=${#MONITORS[@]}
if (( NUM == 0 )); then
    echo "[display/apply-workspaces] no hay monitores enabled" >&2
    exit 1
fi

# Capturamos el monitor enfocado ANTES de aplicar reglas — al cambiar las
# reglas, un workspace puede "viajar" a otro monitor y arrastrarte con él.
ORIG_MON=$(hyprctl -j activeworkspace 2>/dev/null | jq -r '.monitor // empty')

# 1) Regenerar workspaces.lua con las reglas literales del set actual.
{
    echo "-- Auto-generado por hyprland/scripts/display/apply-workspaces.sh"
    echo "-- Fuente: ~/.config/settings/quickshell/config.json"
    echo "-- NO EDITAR A MANO: cualquier cambio se sobreescribe al guardar display."
    echo ""
    for m_idx in "${!MONITORS[@]}"; do
        mon="${MONITORS[$m_idx]}"
        for s in $(seq 1 "$GROUP_SIZE"); do
            ws=$(( m_idx * GROUP_SIZE + s ))
            echo "hl.workspace_rule({ workspace = \"${ws}\", monitor = \"${mon}\", persistent = true })"
        done
    done
} > "${WORKSPACES_LUA}.tmp" && mv "${WORKSPACES_LUA}.tmp" "$WORKSPACES_LUA"

# 2) Aplicar reglas vía dispatch + armar set target para el cleanup.
declare -A TARGET_WS
for m_idx in "${!MONITORS[@]}"; do
    mon="${MONITORS[$m_idx]}"
    for s in $(seq 1 "$GROUP_SIZE"); do
        ws=$(( m_idx * GROUP_SIZE + s ))
        hyprctl dispatch \
            "hl.workspace_rule({workspace = \"${ws}\", monitor = \"${mon}\", persistent = true})" \
            >/dev/null 2>&1
        TARGET_WS[$ws]=1
    done
done

# 3) Cleanup: mover ventanas de CUALQUIER workspace que no esté en TARGET_WS
#    al ws 1. Cubre tanto reglas persistentes huérfanas como workspaces de
#    grupos superiores (creados al navegar más allá del primer grupo) cuyo
#    monitor ya no existe o cambió de orden.
FALLBACK_WS=1

# (a) Cualquier workspace existente con ventanas que NO esté en TARGET_WS:
#     mover sus apps al fallback.
mapfile -t EXISTING_WS < <(
    hyprctl clients -j 2>/dev/null | jq -r '.[].workspace.id' | sort -u | grep -v '^-' || true
)
for ws in "${EXISTING_WS[@]}"; do
    [[ -z "$ws" ]] && continue
    [[ -n "${TARGET_WS[$ws]:-}" ]] && continue
    (( ws == FALLBACK_WS )) && continue

    while IFS= read -r addr; do
        [[ -z "$addr" ]] && continue
        hyprctl dispatch \
            "hl.dsp.window.move({window = \"address:${addr}\", workspace = \"${FALLBACK_WS}\", follow = false})" \
            >/dev/null 2>&1
    done < <(
        hyprctl clients -j 2>/dev/null \
            | jq -r --argjson ws "$ws" '.[] | select(.workspace.id == $ws) | .address'
    )
done

# (b) Quitar persistent=true de reglas que ya no están en TARGET_WS,
#     para que esos workspaces vacíos desaparezcan.
mapfile -t CURRENT_PERSISTENT < <(
    hyprctl workspacerules -j 2>/dev/null \
        | jq -r '.[] | select(.persistent == true and ((.workspaceString | tonumber?) != null)) | .workspaceString'
)
for ws in "${CURRENT_PERSISTENT[@]}"; do
    [[ -z "${TARGET_WS[$ws]:-}" ]] || continue
    (( ws == FALLBACK_WS )) && continue
    hyprctl dispatch \
        "hl.workspace_rule({workspace = \"${ws}\", persistent = false})" \
        >/dev/null 2>&1
done

# 4) Reset de foco (cuando cambia perMonitor / enabled set / order).
if $RESET_FOCUS; then
    for m_idx in "${!MONITORS[@]}"; do
        first_slot=$(( m_idx * GROUP_SIZE + 1 ))
        hyprctl dispatch "hl.dsp.focus({workspace = \"${first_slot}\"})" >/dev/null 2>&1
    done

    if [[ -n "$ORIG_MON" ]]; then
        for m_idx in "${!MONITORS[@]}"; do
            if [[ "${MONITORS[$m_idx]}" == "$ORIG_MON" ]]; then
                hyprctl dispatch "hl.dsp.focus({workspace = \"$(( m_idx * GROUP_SIZE + 1 ))\"})" \
                    >/dev/null 2>&1
                break
            fi
        done
    fi
fi
