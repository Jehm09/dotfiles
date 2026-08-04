#!/usr/bin/env bash
# Login health check for third-party KWin effects.
#
# KWin effect plugins are compiled against KWin's unstable internal API. After a
# kwin upgrade they silently stop loading — no error, no notification, the
# rounded corners just quietly disappear.
#
# The upstream project (matinlotfali/KDE-Rounded-Corners) ships an autorun script
# that rebuilds itself when this happens, but that automation is part of its
# build-from-source flow and is NOT in the AUR package: the package installs only
# the plugin, the shaders and translations. Hence this check.
#
# It deliberately notifies instead of rebuilding on its own: reinstalling an AUR
# package needs sudo, and a login script silently asking for root is worse than a
# notification with the one command to run.

set -uo pipefail

APP_NAME="KWin"
QDBUS="$(command -v qdbus6 || command -v qdbus || true)"
[[ -n "$QDBUS" ]] || exit 0

# effect id : AUR package that provides it
EFFECTS=(
    "kwin4_effect_shapecorners:kwin-effect-rounded-corners"
)

# Wait for KWin's DBus interface; on login this script can start before it is up.
for _ in {1..30}; do
    "$QDBUS" org.kde.KWin /Effects >/dev/null 2>&1 && break
    sleep 1
done

broken=()
for entry in "${EFFECTS[@]}"; do
    effect="${entry%%:*}"
    pkg="${entry##*:}"

    pacman -Qq "$pkg" >/dev/null 2>&1 || continue   # not installed, nothing to check

    # Enabled in kwinrc but not actually loaded == built against an older KWin.
    enabled="$(kreadconfig6 --file kwinrc --group Plugins --key "${effect}Enabled" 2>/dev/null)"
    [[ "$enabled" == "true" ]] || continue

    loaded="$("$QDBUS" org.kde.KWin /Effects org.kde.kwin.Effects.isEffectLoaded "$effect" 2>/dev/null)"
    if [[ "$loaded" != "true" ]]; then
        # One retry through loadEffect: a cold session sometimes just needs the nudge.
        "$QDBUS" org.kde.KWin /Effects org.kde.kwin.Effects.loadEffect "$effect" >/dev/null 2>&1
        sleep 1
        loaded="$("$QDBUS" org.kde.KWin /Effects org.kde.kwin.Effects.isEffectLoaded "$effect" 2>/dev/null)"
    fi

    [[ "$loaded" == "true" ]] || broken+=("$pkg")
done

[[ ${#broken[@]} -eq 0 ]] && exit 0

pkgs="${broken[*]}"
notify-send -a "$APP_NAME" -u normal \
    "Efectos de KWin sin cargar" \
    "Un update de KWin ($(pacman -Q kwin | awk '{print $2}')) los dejó incompatibles.\nRecompila con:\n<b>paru -S --rebuild ${pkgs}</b>" \
    2>/dev/null || true

echo "KWin effects failed to load, rebuild needed: $pkgs" >&2
