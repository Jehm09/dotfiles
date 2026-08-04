#!/usr/bin/env bash
# idle-inhibit-guard.sh
# Pausa hypridle (SIGSTOP) mientras aplique una condición de inhibición, y lo
# reanuda (SIGCONT) cuando deja de aplicar. Es un puente fiable e independiente
# del protocolo wayland idle-inhibit, que tras Hyprland 0.56 dejó de suspender
# los timeouts de hypridle de forma fiable (juegos a pantalla completa y el
# botón "Keep system awake" de quickshell ya no evitaban el apagado de pantalla).
#
# Inhibe (pausa hypridle) cuando:
#   1) Hay una ventana en fullscreen real (juegos / vídeo a pantalla completa).
#   2) El botón "Keep system awake" de quickshell está activo
#      (states.json -> idle.inhibit == true).
#
# Se lanza desde execs.lua al iniciar Hyprland.

set -uo pipefail

STATES_JSON="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/states.json"
LOCK="/run/user/$(id -u)/idle-inhibit-guard.pid"
POLL="${IDLE_GUARD_POLL:-3}"

# Instancia única.
if [[ -f "$LOCK" ]] && kill -0 "$(cat "$LOCK" 2>/dev/null)" 2>/dev/null; then
    exit 0
fi
echo $$ > "$LOCK"
# Al salir, quitar lock y NO dejar hypridle congelado.
trap 'rm -f "$LOCK"; pkill -CONT -x hypridle 2>/dev/null' EXIT INT TERM

should_inhibit() {
    # 1) Ventana fullscreen real (fullscreen >= 2). fullscreen == 1 es maximizado.
    hyprctl -j clients 2>/dev/null | jq -e 'any(.[]; .fullscreen >= 2)' >/dev/null 2>&1 && return 0
    # 2) Keep-awake manual de quickshell.
    [[ -f "$STATES_JSON" ]] && jq -e '.idle.inhibit == true' "$STATES_JSON" >/dev/null 2>&1 && return 0
    return 1
}

hypridle_stopped() {
    local st
    st=$(ps -o state= -C hypridle 2>/dev/null | head -1 | tr -d '[:space:]')
    [[ "$st" == T* ]]
}

while true; do
    if should_inhibit; then
        hypridle_stopped || pkill -STOP -x hypridle 2>/dev/null
    else
        hypridle_stopped && pkill -CONT -x hypridle 2>/dev/null
    fi
    sleep "$POLL"
done
