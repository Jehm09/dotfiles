#!/usr/bin/env bash
# Shared helpers for the KDE utility scripts. Sourced, not executed.
#
# Why these scripts exist: grim and slurp do NOT work under KWin — KWin does not
# implement wlr-screencopy-unstable-v1. Region capture is therefore delegated to
# spectacle, which talks to KWin's own screenshot protocol.

APP_NAME="${APP_NAME:-KDE}"

die() {
    notify-send -a "$APP_NAME" -u critical "$APP_NAME" "$1" 2>/dev/null || true
    echo "ERROR: $1" >&2
    exit 1
}

require() {
    for bin in "$@"; do
        command -v "$bin" >/dev/null 2>&1 || die "Falta '$bin'. Instálalo y vuelve a intentarlo."
    done
}

# copy_text — copy stdin to the clipboard as plain text.
#
# Klipper (plasmashell) owns the clipboard on Plasma and keeps the history, so
# hand the text to it directly over DBus. wl-copy also speaks the standard
# wl_data_device protocol that KWin implements, but it daemonizes to serve the
# selection and the content can be lost when that helper goes away; Klipper's
# own API has no such window. wl-copy stays as the fallback for a session where
# Klipper is disabled.
copy_text() {
    local text qdbus_bin=""
    text="$(cat)"

    for b in qdbus6 qdbus-qt6 qdbus; do
        command -v "$b" >/dev/null 2>&1 && { qdbus_bin="$b"; break; }
    done

    if [[ -n "$qdbus_bin" ]] \
       && "$qdbus_bin" org.kde.klipper /klipper setClipboardContents "$text" >/dev/null 2>&1; then
        return 0
    fi

    command -v wl-copy >/dev/null 2>&1 || die "Ni Klipper ni wl-copy disponibles."
    printf '%s' "$text" | wl-copy
}

# capture_region <output-path>
# Interactive rectangular selection saved to <output-path>.
# Returns 1 (without an error notification) if the user cancelled the selection.
#   -r  rectangular region    -b  background, no GUI
#   -n  no notification       -o  output file
#   -k  accept the region on click-and-release
#
# -k is what makes this a ONE-SHOT capture. Without it Spectacle 6.7 keeps the
# selection overlay open after the drag and waits for confirmation, showing its
# Copy / Save / Extract Text toolbar — so every capture needed a second click.
# -b does NOT suppress that toolbar; it only suppresses the main window.
capture_region() {
    local out="$1"
    require spectacle

    rm -f "$out"
    spectacle -r -b -n -k -o "$out" >/dev/null 2>&1 || true

    # Spectacle can return before the file is flushed to disk; give it a moment.
    local i
    for ((i = 0; i < 40; i++)); do
        [[ -s "$out" ]] && return 0
        sleep 0.05
    done
    return 1
}
