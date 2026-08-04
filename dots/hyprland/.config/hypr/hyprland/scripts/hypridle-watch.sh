#!/usr/bin/env bash
# Vigila ~/.config/hypr/hypridle.conf y reinicia hypridle cuando cambia.
# hypridle no soporta recarga en caliente (no responde a SIGHUP), por lo
# que la única forma de aplicar cambios es matar el proceso y relanzarlo.

CFG="$HOME/.config/hypr/hypridle.conf"
LOCK="/run/user/$(id -u)/hypridle-watch.pid"

if [[ -f "$LOCK" ]] && kill -0 "$(cat "$LOCK" 2>/dev/null)" 2>/dev/null; then
    exit 0
fi
echo $$ > "$LOCK"
trap 'rm -f "$LOCK"; kill 0 2>/dev/null' EXIT INT TERM

command -v inotifywait >/dev/null 2>&1 || {
    notify-send "hypridle-watch" "inotifywait no instalado (paquete inotify-tools)" -u critical 2>/dev/null
    exit 1
}

restart_hypridle() {
    pkill -x hypridle 2>/dev/null
    # Esperar a que el proceso muera (máx ~1s)
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        pgrep -x hypridle >/dev/null 2>&1 || break
        sleep 0.1
    done
    setsid hypridle >/dev/null 2>&1 < /dev/null &
    disown 2>/dev/null
    notify-send "hypridle" "Configuración recargada" -t 2000 2>/dev/null
}

watch_dir="$(dirname "$CFG")"
base="$(basename "$CFG")"

inotifywait -m -q -e close_write,moved_to,create --format '%f' "$watch_dir" |
while read -r fname; do
    [[ "$fname" != "$base" ]] && continue
    sleep 0.15  # debounce
    [[ -f "$CFG" ]] || continue
    restart_hypridle
done
