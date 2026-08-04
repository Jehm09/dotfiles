#!/usr/bin/env bash
# Applies the whole appearance stack. Run with: setup kde theme
#
# Why a script and not just files: a Plasma 6 global theme is applied, not
# copied. The *packages* live in ~/.local/share (those are vendored and handled
# by `setup kde apply`), but *selecting* them writes a dozen keys across kwinrc,
# kdeglobals, plasmarc and kcminputrc. plasma-apply-lookandfeel does most of it
# in one shot, and the rest is set explicitly here so nothing depends on what a
# previous theme happened to leave behind.
#
# Order matters: the look-and-feel goes first because it overwrites decoration,
# colour scheme, Plasma style, widget style, icons AND cursor. Everything set
# after it is an intentional override on top.

set -euo pipefail

_have() { command -v "$1" >/dev/null 2>&1; }
_qdbus="$(command -v qdbus6 || command -v qdbus || true)"

say() { printf '  %-26s %s\n' "$1" "$2"; }

# ── Fonts: kept across both variants; these are the user's, not the rice's ───
apply_fonts() {
    kwriteconfig6 --file kdeglobals --group General --key font \
        "Google Sans Flex,11,-1,5,500,0,0,0,0,0,0,0,0,0,0,1,Medium"
    kwriteconfig6 --file kdeglobals --group General --key fixed \
        "JetBrainsMono Nerd Font,11,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
    kwriteconfig6 --file kdeglobals --group General --key menuFont \
        "Google Sans Flex,10,-1,5,500,0,0,0,0,0,0,0,0,0,0,1,Medium"
    kwriteconfig6 --file kdeglobals --group General --key toolBarFont \
        "Google Sans Flex,10,-1,5,500,0,0,0,0,0,0,0,0,0,0,1,Medium"
    kwriteconfig6 --file kdeglobals --group General --key smallestReadableFont \
        "Google Sans Flex,9,-1,5,500,0,0,0,0,0,0,0,0,0,0,1,Medium"
    say "fuentes" "Google Sans Flex / JetBrainsMono NF"
}

# ── KWin effects that are part of the look ──────────────────────────────────
apply_effects() {
    if pacman -Qq kwin-effect-rounded-corners >/dev/null 2>&1; then
        kwriteconfig6 --file kwinrc --group Plugins \
            --key kwin4_effect_shapecornersEnabled true
        # `reconfigure` alone does not load a newly enabled third-party effect in
        # a live session; loadEffect does.
        [[ -n "$_qdbus" ]] && "$_qdbus" org.kde.KWin /Effects \
            org.kde.kwin.Effects.loadEffect kwin4_effect_shapecorners >/dev/null 2>&1 || true
        say "esquinas redondeadas" "activadas"
    fi
}

echo "Aplicando Scratchy..."
if _have plasma-apply-lookandfeel; then
    # --resetLayout is deliberately NOT passed: it would replace the panel, which
    # is managed separately by `setup kde panel`.
    plasma-apply-lookandfeel --apply Scratchy >/dev/null
    say "global theme" "Scratchy"
fi
# Re-assert each piece: applying a look-and-feel does not reliably set all of them.
kwriteconfig6 --file kwinrc     --group org.kde.kdecoration2 --key library "org.kde.kwin.aurorae.v2"
kwriteconfig6 --file kwinrc     --group org.kde.kdecoration2 --key theme   "__aurorae__svg__Scratchy"
kwriteconfig6 --file kdeglobals --group General --key ColorScheme "Scratchy"
kwriteconfig6 --file plasmarc   --group Theme   --key name        "Scratchy"
say "decoración" "Scratchy (aurorae)"
say "plasma style" "Scratchy"

# ── Applied on top of the global theme ──────────────────────────────────────
# Window buttons on the right, three of them: minimise, maximise, close.
kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key ButtonsOnLeft  ""
kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key ButtonsOnRight "IAX"
say "botones" "derecha (IAX)"

# Icons: YAMIS if present, otherwise leave whatever the theme picked.
if [[ -d "$HOME/.local/share/icons/YAMIS" || -d /usr/share/icons/YAMIS ]]; then
    kwriteconfig6 --file kdeglobals --group Icons --key Theme "YAMIS"
    say "iconos" "YAMIS"
else
    say "iconos" "YAMIS no instalado — ver dots/kde/VENDORED.md"
fi

# Cursor: applying a look-and-feel resets this, so it is set last.
# Bibata-Modern-Classic (package bibata-cursor-theme) for both variants — it is
# the cursor in use, and it carried over from the Hyprland setup.
CURSOR="Bibata-Modern-Classic"
if [[ -d "/usr/share/icons/$CURSOR" || -d "$HOME/.local/share/icons/$CURSOR" || -d "$HOME/.icons/$CURSOR" ]]; then
    kwriteconfig6 --file kcminputrc --group Mouse --key cursorTheme "$CURSOR"
    kwriteconfig6 --file kcminputrc --group Mouse --key cursorSize  24
    say "cursor" "$CURSOR 24"
else
    say "cursor" "$CURSOR no instalado (paquete bibata-cursor-theme)"
fi

apply_fonts
apply_effects

# ── Reload what can be reloaded ─────────────────────────────────────────────
if [[ -n "$_qdbus" ]]; then
    "$_qdbus" org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
fi

echo
echo "Listo. Cierra sesión y vuelve a entrar para que cuaje del todo:"
echo "  el estilo de widgets y los iconos no se recargan en caliente en todas las apps."
