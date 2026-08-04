#!/usr/bin/env bash
# KDE Plasma profile manager.
#
# Unlike the rest of the dotfiles (see symlink.sh), the Plasma config is managed
# by COPY, not by symlink. KConfig rewrites these files on every settings change
# and again on logout, using a write-temp-then-rename pattern that turns symlinks
# into regular files. Copying keeps the repo in control of when changes move.
#
# Which files are managed is declared in dots/kde/files.list.
#
# Absolute home paths are stored as the placeholder @HOME@ and substituted on the
# way in and out, so the profile works on any machine / username.
#
# Usage:
#   ./cmd/lib/kde.sh apply    [--dry-run]   repo -> ~   (backs up what it replaces)
#   ./cmd/lib/kde.sh save     [--dry-run]   ~ -> repo   (what you commit)
#   ./cmd/lib/kde.sh diff                   show differences, change nothing
#   ./cmd/lib/kde.sh panels                 rebuild panels from dots/kde/panels.js
#                                           (destructive: drops every panel first)

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROFILE_DIR="$DOTFILES_DIR/dots/kde"
FILES_LIST="$PROFILE_DIR/files.list"

source "$DOTFILES_DIR/cmd/lib/utils.sh"

MODE=""
DRY_RUN=false
PANEL_RESTORE=false

for arg in "$@"; do
    case "$arg" in
        apply|save|diff|panels|theme|panel) MODE="$arg" ;;
        --restore)       PANEL_RESTORE=true ;;
        --dry-run)       DRY_RUN=true ;;
        -h|--help)
            sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
            exit 0
            ;;
        *) error "Argumento desconocido: $arg"; exit 1 ;;
    esac
done

if [[ -z "$MODE" ]]; then
    error "Falta el modo. Usa: apply | save | diff"
    exit 1
fi

# ------------------------------------------------------------------
# panel: save or restore the hand-built panel layout.
#
# Kept out of apply/save on purpose. plasma-org.kde.plasma.desktop-appletsrc is
# owned by plasmashell, which rewrites it from memory on exit — so a restore only
# sticks with plasmashell stopped, and a blind `apply` while a session runs would
# silently lose the panel. It also holds every panel widget's configuration,
# including Panel Colorizer's 55 kB globalSettings JSON, which is why the whole
# file is copied rather than reconstructed from a script.
#
#   setup kde panel             live -> repo   (what you commit)
#   setup kde panel --restore   repo -> live   (stops plasmashell, then restarts)
# ------------------------------------------------------------------
if [[ "$MODE" == panel ]]; then
    PANEL_REPO="$PROFILE_DIR/panel/plasma-org.kde.plasma.desktop-appletsrc"
    PANEL_LIVE="$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"

    if [[ "$PANEL_RESTORE" == false ]]; then
        [[ -f "$PANEL_LIVE" ]] || { error "No existe $PANEL_LIVE"; exit 1; }
        if [[ "$DRY_RUN" == true ]]; then
            info "[dry-run] Copiaría el panel vivo -> $PANEL_REPO"; exit 0
        fi
        mkdir -p "$(dirname "$PANEL_REPO")"
        sed "s|${HOME}|@HOME@|g" "$PANEL_LIVE" > "$PANEL_REPO"
        success "Panel guardado en el repo."
        echo "  Ojo: [ScreenMapping] y lastScreen= son específicos de esta máquina."
        echo "  En otro PC con distinto número/orden de monitores puede aparecer en la pantalla equivocada."
        exit 0
    fi

    [[ -f "$PANEL_REPO" ]] || { error "No hay panel guardado en $PANEL_REPO"; exit 1; }
    if [[ "$DRY_RUN" == true ]]; then
        info "[dry-run] Restauraría $PANEL_REPO -> $PANEL_LIVE (parando plasmashell)"; exit 0
    fi

    _bk="$HOME/.config/backup/plasma-appletsrc.before-restore.$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$(dirname "$_bk")"
    [[ -f "$PANEL_LIVE" ]] && cp -a "$PANEL_LIVE" "$_bk" && info "Backup del panel actual: $_bk"

    if pgrep -x plasmashell >/dev/null 2>&1; then
        info "Parando plasmashell (si no, reescribe el fichero al salir)..."
        systemctl --user stop plasma-plasmashell.service
        sleep 1
        _restart=true
    else
        _restart=false
    fi

    sed "s|@HOME@|${HOME}|g" "$PANEL_REPO" > "$PANEL_LIVE"
    success "Panel restaurado."

    if [[ "$_restart" == true ]]; then
        systemctl --user start plasma-plasmashell.service
        info "plasmashell reiniciado."
    else
        echo "  Entra en la sesión de Plasma para verlo."
    fi
    exit 0
fi

# ------------------------------------------------------------------
# theme: apply the appearance stack (global theme, decoration, colours, icons,
# cursor, fonts, effects). Separate from apply/save because a Plasma theme is
# *selected*, not copied: the packages are files, but choosing them writes keys
# across kwinrc/kdeglobals/plasmarc/kcminputrc. See dots/kde/theme.sh.
# ------------------------------------------------------------------
if [[ "$MODE" == theme ]]; then
    THEME_SH="$PROFILE_DIR/theme.sh"
    [[ -f "$THEME_SH" ]] || { error "No existe $THEME_SH"; exit 1; }

    if [[ "$DRY_RUN" == true ]]; then
        info "[dry-run] Ejecutaría $THEME_SH"
        exit 0
    fi

    bash "$THEME_SH"
    exit 0
fi

# ------------------------------------------------------------------
# panels: rebuild the panel layout through Plasma's scripting API.
# Kept separate from apply/save because plasmashell owns
# plasma-org.kde.plasma.desktop-appletsrc and rewrites it live — copying that
# file around does not work, scripting it does. See dots/kde/panels.js.
# ------------------------------------------------------------------
if [[ "$MODE" == panels ]]; then
    PANELS_JS="$PROFILE_DIR/panels.js"
    [[ -f "$PANELS_JS" ]] || { error "No existe $PANELS_JS"; exit 1; }
    pgrep -x plasmashell >/dev/null 2>&1 || { error "plasmashell no está corriendo: entra en la sesión de Plasma primero."; exit 1; }

    _qdbus="$(command -v qdbus6 || command -v qdbus || true)"
    [[ -n "$_qdbus" ]] || { error "No encuentro qdbus6/qdbus (paquete qt6-tools)."; exit 1; }

    if [[ "$DRY_RUN" == true ]]; then
        info "[dry-run] Ejecutaría $PANELS_JS contra plasmashell. Reconstruye TODOS los paneles."
        exit 0
    fi

    warn "Esto elimina y recrea todos los paneles. El layout actual se pierde."
    info "Ejecutando $PANELS_JS..."
    "$_qdbus" org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$(cat "$PANELS_JS")"

    # Panel opacity cannot be set from the scripting API: Panel.opacity is
    # read-only there (assigning a string or an int is silently ignored, and the
    # getter reports "adaptive" regardless of the stored config). The real
    # property is PanelView::opacityMode, owned by plasmashell and persisted in
    # the containment group of plasma-org.kde.plasma.desktop-appletsrc.
    #
    # plasmashell rewrites that file from memory on exit, so the write only
    # sticks with plasmashell stopped.
    #   opacityMode: 0 = adaptive, 1 = opaque, 2 = translucent
    #   location:    3 = top edge, 4 = bottom edge
    _appletsrc="$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"
    _cid=""
    _cid="$(awk '
        /^\[Containments\]\[[0-9]+\]$/ { id=$0; gsub(/[^0-9]/,"",id); loc=""; plug="" }
        /^location=/  { loc=$0 }
        /^plugin=/    { plug=$0 }
        loc=="location=3" && plug=="plugin=org.kde.panel" { print id; exit }
    ' "$_appletsrc" 2>/dev/null)"

    if [[ -n "$_cid" ]]; then
        info "Panel superior = containment $_cid; poniendo opacityMode=1 (opaque)..."
        systemctl --user stop plasma-plasmashell.service
        sleep 1
        kwriteconfig6 --file plasma-org.kde.plasma.desktop-appletsrc \
            --group Containments --group "$_cid" --key opacityMode 1
        systemctl --user start plasma-plasmashell.service
        sleep 3
    else
        warn "No localicé el containment del panel superior; opacidad sin cambiar."
    fi

    success "Paneles reconstruidos."
    exit 0
fi

[[ -f "$FILES_LIST" ]] || { error "No existe $FILES_LIST"; exit 1; }

[[ "$DRY_RUN" == true ]] && info "[dry-run] No se hará ningún cambio."

# ------------------------------------------------------------------
# Entry expansion
# Reads files.list (comments and inline comments stripped) and expands entries
# ending in "/" into their individual files, walking whichever side is the
# source for this run.
# ------------------------------------------------------------------
_raw_entries() {
    grep -v '^\s*#' "$FILES_LIST" | grep -v '^\s*$' | awk '{print $1}'
}

# expand_entries <root>  ->  one $HOME-relative path per line
# Matches regular files AND symlinks: icon themes are mostly symlinks (YAMIS is
# 3956 files plus 2070 links), and a plain -type f would drop every link and
# leave a half-broken theme.
expand_entries() {
    local root="$1" entry
    while read -r entry; do
        if [[ "$entry" == */ ]]; then
            [[ -d "$root/$entry" ]] || continue
            (cd "$root" && find "$entry" \( -type f -o -type l \) -printf '%p\n' 2>/dev/null) || true
        else
            echo "$entry"
        fi
    done < <(_raw_entries)
}

# ------------------------------------------------------------------
# Placeholder substitution
# Text files only — binaries are copied byte for byte.
# ------------------------------------------------------------------
_is_text() { grep -Iq . "$1" 2>/dev/null; }

# render <src> <direction>  ->  transformed content on stdout
# direction: to_home (@HOME@ -> $HOME) | to_repo ($HOME -> @HOME@)
render() {
    local src="$1" direction="$2"
    if ! _is_text "$src"; then
        cat "$src"
    elif [[ "$direction" == to_home ]]; then
        sed "s|@HOME@|${HOME}|g" "$src"
    else
        sed "s|${HOME}|@HOME@|g" "$src"
    fi
}

# ------------------------------------------------------------------
# Modes
# ------------------------------------------------------------------
case "$MODE" in
    apply) SRC_ROOT="$PROFILE_DIR"; DST_ROOT="$HOME"; DIRECTION=to_home ;;
    save)  SRC_ROOT="$HOME"; DST_ROOT="$PROFILE_DIR"; DIRECTION=to_repo ;;
    diff)  SRC_ROOT="$PROFILE_DIR"; DST_ROOT="$HOME"; DIRECTION=to_home ;;
esac

if [[ "$MODE" == apply && "$DRY_RUN" == false ]] && pgrep -x plasmashell >/dev/null 2>&1; then
    warn "Hay una sesión de Plasma corriendo: sobrescribirá estos ficheros al cerrar sesión."
    warn "Aplica desde otra sesión (Hyprland o TTY), o cierra sesión justo después."
    read -rp "  ¿Continuar de todos modos? [y/N] " _yn
    [[ "$_yn" =~ ^[Yy]$ ]] || { info "Cancelado."; exit 0; }
fi

BACKUP_DIR="$HOME/.config/backup/kde.$(date +%Y%m%d_%H%M%S)"
_backup_made=false

_n_changed=0
_n_same=0
_n_missing=0

while read -r rel; do
    [[ -z "$rel" ]] && continue
    src="$SRC_ROOT/$rel"
    dst="$DST_ROOT/$rel"

    # ── Symlinks are recreated as symlinks, never dereferenced ───────────────
    # Handled before the -f test, because -f follows the link and is false for a
    # dangling one — and inside an icon theme the target may not have been copied
    # yet. Copying the content instead of the link would bloat the tree and lose
    # the theme's structure.
    if [[ -L "$src" ]]; then
        target="$(readlink "$src")"
        # Only matters if the link target is absolute and points inside $HOME.
        if [[ "$DIRECTION" == to_home ]]; then
            target="${target//@HOME@/$HOME}"
        else
            target="${target//$HOME/@HOME@}"
        fi

        if [[ -L "$dst" && "$(readlink "$dst")" == "$target" ]]; then
            ((_n_same++)) || true
            continue
        fi

        ((_n_changed++)) || true

        if [[ "$MODE" == diff ]]; then
            echo "[symlink]   $rel  ->  $target"
            continue
        fi
        if [[ "$DRY_RUN" == true ]]; then
            echo "[enlazaría] $rel  ->  $target"
            continue
        fi

        mkdir -p "$(dirname "$dst")"
        ln -sfn "$target" "$dst"
        echo "[symlink]   $rel"
        continue
    fi

    if [[ ! -f "$src" ]]; then
        echo "[ausente]   $rel"
        ((_n_missing++)) || true
        continue
    fi

    tmp="$(mktemp)"
    render "$src" "$DIRECTION" > "$tmp"

    # A symlinked destination always counts as "differs": the profile owns real
    # files, so it must be converted even when the content already matches.
    if [[ -f "$dst" && ! -L "$dst" ]] && cmp -s "$tmp" "$dst"; then
        rm -f "$tmp"
        ((_n_same++)) || true
        continue
    fi

    ((_n_changed++)) || true

    if [[ "$MODE" == diff ]]; then
        echo ""
        echo "--- repo: $rel"
        echo "+++ ~/$rel"
        diff -u "$tmp" "$([[ -f "$dst" ]] && echo "$dst" || echo /dev/null)" | tail -n +3 || true
        rm -f "$tmp"
        continue
    fi

    if [[ "$DRY_RUN" == true ]]; then
        if [[ -f "$dst" ]]; then
            echo "[cambiaría] $rel"
        else
            echo "[crearía]   $rel"
        fi
        rm -f "$tmp"
        continue
    fi

    # Back up the file we are about to replace (apply only — on save the repo is
    # under git, which is backup enough).
    if [[ "$MODE" == apply && -e "$dst" ]]; then
        mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
        # -a preserves a symlink as a symlink, so --unlink-style recovery stays possible.
        cp -a "$dst" "$BACKUP_DIR/$rel"
        _backup_made=true

        # Files that symlink.sh used to manage (kdeglobals, dolphinrc) now belong
        # to this profile. Replacing the symlink with a real file is intended, but
        # it is a one-way change, so say so out loud.
        if [[ -L "$dst" ]]; then
            warn "$rel era un symlink a $(readlink "$dst")"
            warn "  se sustituye por un fichero real gestionado por el perfil KDE"
            rm -f "$dst"
        fi
    fi

    mkdir -p "$(dirname "$dst")"
    mv "$tmp" "$dst"
    chmod --reference="$src" "$dst"

    echo "[copiado]   $rel"
done < <(expand_entries "$SRC_ROOT")

# ------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------
echo ""
case "$MODE" in
    diff)
        if [[ $_n_changed -eq 0 ]]; then
            success "Sin diferencias ($_n_same ficheros iguales, $_n_missing ausentes)."
        else
            info "$_n_changed con diferencias, $_n_same iguales, $_n_missing ausentes."
        fi
        ;;
    apply)
        if [[ "$DRY_RUN" == true ]]; then
            info "Dry run: $_n_changed cambiarían, $_n_same ya correctos, $_n_missing ausentes."
        else
            success "Perfil KDE aplicado: $_n_changed copiados, $_n_same sin cambios, $_n_missing ausentes."
            [[ "$_backup_made" == true ]] && info "Backup de lo reemplazado en: $BACKUP_DIR"
            echo "  Cierra sesión y vuelve a entrar en Plasma para que tome efecto."
            echo "  Si has tocado los .desktop:  kbuildsycoca6 && systemctl --user restart plasma-kglobalaccel"
        fi
        ;;
    save)
        if [[ "$DRY_RUN" == true ]]; then
            info "Dry run: $_n_changed se guardarían, $_n_same sin cambios, $_n_missing ausentes."
        else
            success "Perfil KDE guardado en el repo: $_n_changed actualizados, $_n_same sin cambios, $_n_missing ausentes."
            echo "  Revisa con 'git -C $DOTFILES_DIR diff' antes de commitear."
        fi
        ;;
esac
