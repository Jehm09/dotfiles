#!/usr/bin/env bash
# Variables compartidas para scripts de Hyprland.
# Sourcear con: source "$(dirname "${BASH_SOURCE[0]}")/../env.sh"

CONFIG_JSON="${XDG_CONFIG_HOME:-$HOME/.config}/settings/quickshell/config.json"
HYPR_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"

# Retorna los monitores habilitados en el orden definido en display.order (uno por línea).
enabled_monitors_ordered() {
    jq -r '[.display.order[] as $n | (.display.monitors[] | select(.name == $n and .enabled != false) | .name)][]' "$CONFIG_JSON"
}
