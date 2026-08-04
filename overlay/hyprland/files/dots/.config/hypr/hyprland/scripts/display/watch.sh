#!/usr/bin/env bash
# Vigila el config.json de quickshell y aplica automáticamente
# los cambios en display.monitors, display.order y display.workspaces.

DIR="$(dirname "$(readlink -f "$0")")"
source "$DIR/../env.sh"
CFG="$CONFIG_JSON"
APPLY_MON="$DIR/apply-monitors.sh"
APPLY_WS="$DIR/apply-workspaces.sh"
LOCK="/run/user/$(id -u)/hypr-display-watch.pid"

# Single-instance: si el PID anterior sigue vivo, salimos.
if [[ -f "$LOCK" ]] && kill -0 "$(cat "$LOCK" 2>/dev/null)" 2>/dev/null; then
    exit 0
fi
echo $$ > "$LOCK"
trap 'rm -f "$LOCK"; kill 0 2>/dev/null' EXIT INT TERM

command -v inotifywait >/dev/null 2>&1 || {
    notify-send "display-watch" "inotifywait no instalado (paquete inotify-tools)" -u critical 2>/dev/null
    exit 1
}

# Snapshots de las distintas piezas que nos importan, por separado.
snapshot_mon_full() { jq -c '{m: .display.monitors, o: .display.order}' "$CFG" 2>/dev/null; }
snapshot_order()    { jq -c '.display.order' "$CFG" 2>/dev/null; }
snapshot_enabled()  { jq -c '[.display.monitors[] | select(.enabled != false) | .name] | sort' "$CFG" 2>/dev/null; }
snapshot_perMon()   { jq -r '.display.workspaces.perMonitor // 5' "$CFG" 2>/dev/null; }
snapshot_ws_full()  { jq -c '.display.workspaces' "$CFG" 2>/dev/null; }

prev_mon=$(snapshot_mon_full)
prev_order=$(snapshot_order)
prev_enabled=$(snapshot_enabled)
prev_perMon=$(snapshot_perMon)
prev_ws=$(snapshot_ws_full)

watch_dir="$(dirname "$CFG")"
base="$(basename "$CFG")"

inotifywait -m -q -e close_write,moved_to,create --format '%f' "$watch_dir" |
while read -r fname; do
    [[ "$fname" != "$base" ]] && continue
    sleep 0.15  # debounce
    [[ -f "$CFG" ]] || continue

    cur_mon=$(snapshot_mon_full)
    cur_order=$(snapshot_order)
    cur_enabled=$(snapshot_enabled)
    cur_perMon=$(snapshot_perMon)
    cur_ws=$(snapshot_ws_full)

    monitors_changed=false
    order_changed=false
    workspaces_changed=false
    enabled_changed=false
    perMon_changed=false

    [[ -n "$cur_mon"     && "$cur_mon"     != "$prev_mon"     ]] && monitors_changed=true
    [[ -n "$cur_order"   && "$cur_order"   != "$prev_order"   ]] && order_changed=true
    [[ -n "$cur_ws"      && "$cur_ws"      != "$prev_ws"      ]] && workspaces_changed=true
    [[ -n "$cur_enabled" && "$cur_enabled" != "$prev_enabled" ]] && enabled_changed=true
    [[ -n "$cur_perMon"  && "$cur_perMon"  != "$prev_perMon"  ]] && perMon_changed=true

    if $monitors_changed; then
        "$APPLY_MON" 2>/dev/null
    fi

    # Reglas para disparar init.sh:
    #   - cambió cualquier parte de display.workspaces (perMonitor/cycle)
    #   - cambió el SET de monitores enabled (apareció/desapareció uno)
    #   - cambió el ORDEN de monitores (re-asigna qué ws va a qué monitor)
    # Si el cambio reasigna workspaces a monitores (perMonitor, enabled set,
    # order) hacemos --reset-focus para que cada monitor vaya a su primer slot.
    if $workspaces_changed || $enabled_changed || $order_changed; then
        if $perMon_changed || $enabled_changed || $order_changed; then
            "$APPLY_WS" --reset-focus 2>/dev/null
        else
            "$APPLY_WS" 2>/dev/null
        fi
    fi

    prev_mon="$cur_mon"
    prev_order="$cur_order"
    prev_enabled="$cur_enabled"
    prev_perMon="$cur_perMon"
    prev_ws="$cur_ws"
done
