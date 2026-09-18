#!/usr/bin/env bash
# Variables compartidas para scripts de Hyprland.
# Sourcear con: source "$(dirname "${BASH_SOURCE[0]}")/../env.sh"

CONFIG_JSON="${XDG_CONFIG_HOME:-$HOME/.config}/settings/quickshell/config.json"
HYPR_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"

# Identidad de un monitor: `desc` (descripción del EDID), no `name`.
#
# El nombre de conector (DP-3, HDMI-A-1...) lo asigna el kernel y NO es estable:
# cambia al actualizar el driver de la GPU (una actualización de nvidia-open
# renombró DP-4/DP-5 a DP-2/DP-3) y al mover el cable a otro puerto. La
# descripción del EDID la reporta el propio monitor, así que sobrevive a ambos.
#
# `name` se conserva en el JSON como último puerto visto: sirve de fallback para
# monitores sin EDID legible y para migrar configs viejas que sólo tienen nombre.
_JQ_MONITOR_LIB='
def live_of($e; $live):
    ( first($live[] | select((($e.desc // "") != "") and (.description == $e.desc)))
      // first($live[] | select(.name == ($e.name // "")))
      // null );
def desc_of($e; $live):
    ( ($e.desc // "") as $d
      | if $d != "" then $d
        else ( live_of($e; $live) as $lm
               | if $lm == null then "" else ($lm.description // "") end )
        end );
def selector_of($e; $live):
    ( desc_of($e; $live) as $d
      | if $d != "" then "desc:" + $d else ($e.name // "") end );
def name_of($e; $live):
    ( live_of($e; $live) as $lm
      | if $lm == null then ($e.name // "") else $lm.name end );
def entry_of($key; $mons):
    ( first($mons[] | select((.desc // "") == $key and $key != ""))
      // first($mons[] | select((.name // "") == $key))
      // null );
def ordered($live):
    ( .display as $d
      | (($d.monitors) // []) as $mons
      | [ (($d.order) // [])[] as $k | entry_of($k; $mons) ]
      | map(select(. != null and (.enabled != false))) );
'

# Monitores vivos tal cual los ve Hyprland (name + description).
live_monitors_json() {
    hyprctl -j monitors all 2>/dev/null || echo '[]'
}

# Monitores habilitados, en el orden de display.order, como NOMBRE de conector
# actual. Para comparar contra lo que reporta hyprctl.
enabled_monitors_ordered() {
    jq -r --argjson live "$(live_monitors_json)" \
        "$_JQ_MONITOR_LIB"' ordered($live) | map(name_of(.; $live)) | .[]' "$CONFIG_JSON"
}

# Igual, pero como selector para hl.monitor/hl.workspace_rule: "desc:<EDID>" si
# conocemos la descripción, o el nombre de conector como último recurso.
enabled_monitor_selectors_ordered() {
    jq -r --argjson live "$(live_monitors_json)" \
        "$_JQ_MONITOR_LIB"' ordered($live) | map(selector_of(.; $live)) | .[]' "$CONFIG_JSON"
}
