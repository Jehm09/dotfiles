#!/usr/bin/env bash
# Foco direccional con semántica de Hyprland, y el cursor viaja a la ventana.
#
# Uso: focus-warp.sh left|right|up|down
#
# La selección la hace un script de KWin (focus-dir.js.in) porque:
#
#   - "Switch Window <dir>" de KWin da la vuelta dentro del mismo monitor en vez
#     de cruzar al de al lado, y no es determinista en cuál elige. Tres intentos
#     de envolverlo con lógica correctora no lo arreglaron.
#   - Desde un script de KWin sí se ve workspace.windowList() con la geometría
#     real de todas las ventanas, así que las pantallas se pueden tratar como un
#     único plano continuo: se elige la más cercana en esa dirección esté donde
#     esté, y si no hay ninguna no se hace nada (nunca circular).
#
# El cursor se mueve aparte porque KWin expone workspace.cursorPos como SOLO
# LECTURA (asignarle algo lanza "Cannot assign to read-only property"), así que el
# warp tiene que venir de fuera. ydotool escribe por /dev/uinput y no depende de
# ningún protocolo Wayland que KWin no tenga.

set -euo pipefail

APP_NAME="Focus"
DIR="${1:-}"
case "$DIR" in
    left|right|up|down) ;;
    *) echo "uso: $(basename "$0") left|right|up|down" >&2; exit 2 ;;
esac

_missing() {
    notify-send -a "$APP_NAME" -u critical "Falta $1" "$2" 2>/dev/null || true
    echo "ERROR: falta $1" >&2
    exit 1
}
command -v gdbus   >/dev/null || _missing gdbus   "Instala glib2."
command -v ydotool >/dev/null || _missing ydotool "Instala ydotool y activa ydotool.service."

HERE="$(dirname "$(readlink -f "$0")")"
TPL="$HERE/focus-dir.js.in"
[[ -f "$TPL" ]] || _missing focus-dir.js.in "Falta la plantilla junto a este script."

RUN="${XDG_RUNTIME_DIR:-/tmp}"
JS="$RUN/focus-dir-$DIR.js"
# Regenerar solo si la plantilla es más nueva: evita escribir en cada pulsación.
[[ -f "$JS" && "$JS" -nt "$TPL" ]] || sed "s/@DIR@/$DIR/" "$TPL" > "$JS"

# ── 1. Elegir y activar la ventana destino dentro de KWin ───────────────────
NAME="focusdir$DIR"
gdbus call --session --dest org.kde.KWin --object-path /Scripting \
    --method org.kde.kwin.Scripting.unloadScript "$NAME" >/dev/null 2>&1 || true
gdbus call --session --dest org.kde.KWin --object-path /Scripting \
    --method org.kde.kwin.Scripting.loadScript "$JS" "$NAME" >/dev/null 2>&1
gdbus call --session --dest org.kde.KWin --object-path /Scripting \
    --method org.kde.kwin.Scripting.start >/dev/null 2>&1

# ── 2. Recoger el resultado que imprimió el script ──────────────────────────
# print() de un script de KWin va al journal de kwin_wayland.
target=""
for _ in 1 2 3 4 5 6 7 8; do
    target="$(journalctl --user -b --since '-3s' --no-pager 2>/dev/null \
              | grep -o 'FOCUSDIR [A-Z]* *[-0-9]* *[-0-9]*' | tail -1)"
    [[ -n "$target" ]] && break
    sleep 0.01
done
gdbus call --session --dest org.kde.KWin --object-path /Scripting \
    --method org.kde.kwin.Scripting.unloadScript "$NAME" >/dev/null 2>&1 || true

# Sin ventana en esa dirección: no se mueve nada.
[[ "$target" == FOCUSDIR\ OK* ]] || exit 0
read -r _ _ TX TY <<< "$target"
[[ "$TX" =~ ^-?[0-9]+$ && "$TY" =~ ^-?[0-9]+$ ]] || exit 0

# ── 3. Llevar el cursor al centro de esa ventana ────────────────────────────
# No se usa `ydotool mousemove --absolute`: sus coordenadas no son el espacio
# global del compositor (medido: pedir 3000,800 aterrizaba en 0,360). El
# movimiento relativo sí llega, pero KWin le aplica aceleración (~1.7x), así que
# se converge por realimentación pidiendo el 60 % de lo que falta.
#
# No hay teletransporte real disponible, comprobado:
#   - `ydotool mousemove --absolute` está roto: muestreando de 0 a 65535, TODO
#     valor acaba en 0,360. Sus coordenadas no son el espacio del compositor.
#   - KWin expone workspace.cursorPos como SOLO LECTURA.
#   - Desactivar la aceleración del dispositivo virtual en kcminputrc
#     ([Libinput][9011][26214][ydotoold virtual device], perfil plano) no surtió
#     efecto: el relativo sigue amplificado (~2x en saltos largos).
#
# Así que se mueve en relativo pero en MUY POCOS pasos, para que no se vea volar:
# 2 saltos son ~1 fotograma y se percibe como aparición. La tolerancia es amplia
# a propósito — basta caer dentro de la ventana, no en su centro exacto.
command -v kdotool >/dev/null || exit 0
TOL=60
for _ in 1 2 3; do
    pos="$(kdotool getmouselocation --shell 2>/dev/null | tr '\n' ' ')"
    cx="$(sed -n 's/.*X=\([-0-9]\+\).*/\1/p' <<< "$pos")"
    cy="$(sed -n 's/.*Y=\([-0-9]\+\).*/\1/p' <<< "$pos")"
    [[ "$cx" =~ ^-?[0-9]+$ && "$cy" =~ ^-?[0-9]+$ ]] || break

    dx=$(( TX - cx )); dy=$(( TY - cy ))
    (( ${dx#-} <= TOL && ${dy#-} <= TOL )) && break

    # 55 % compensa la amplificación medida en saltos largos.
    ydotool mousemove -x $(( dx * 55 / 100 )) -y $(( dy * 55 / 100 ))
    sleep 0.006
done
