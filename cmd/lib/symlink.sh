#!/usr/bin/env bash
# Dynamic dotfiles symlink manager.
#
# Reads every entry (file or directory) inside the selected profiles' .config/
# and creates a matching symlink in ~/.config/. Adding a new app config is as
# simple as dropping its folder into a profile and re-running this script.
#
# DESKTOP CHOICE — required, no default
#   hyprland   links  dots/common/  +  dots/hyprland/
#   kde        links  dots/common/  only; the Plasma side is copy-managed and
#              written separately by `setup kde apply` (cmd/lib/kde.sh), because
#              KConfig rewrites its files at runtime and would clobber symlinks.
#
# dots/common/ is shared by both: kitty, fish, yazi, mpv, fastfetch, starship,
# fontconfig and the browser/editor flag files — nothing tied to a compositor.
#
# Usage:
#   ./cmd/lib/symlink.sh hyprland      Link common + hyprland
#   ./cmd/lib/symlink.sh kde           Link common  (then: setup kde apply)
#   ./cmd/lib/symlink.sh kde --dry-run Preview, no changes
#   ./cmd/lib/symlink.sh hyprland --unlink   Remove managed symlinks, restore backups

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
TARGET_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"

DRY_RUN=false
UNLINK=false
DESKTOP=""

_usage() {
    cat <<EOF

Usage: setup dotfiles <hyprland|kde> [--dry-run] [--unlink]

dots/common is linked either way — kitty, fish, fastfetch, yazi, mpv, starship,
fontconfig and the browser/editor flag files. Nothing there is tied to a
compositor, so both desktops get the same terminal and CLI setup.

The argument only decides what is linked ON TOP of that:

    hyprland    + the graphical side: hypr, quickshell, fuzzel, matugen,
                  Kvantum, wlogout  (from the upstream clone, see setup upstream)
    kde         + nothing here — Plasma is copy-managed, applied separately
                  with 'setup kde apply'

EOF
}

for arg in "$@"; do
    case "$arg" in
        hyprland|kde) DESKTOP="$arg" ;;
        --dry-run)    DRY_RUN=true   ;;
        --unlink)     UNLINK=true    ;;
        -h|--help)    _usage; exit 0 ;;
        *) echo "ERROR: unknown argument: $arg"; _usage; exit 1 ;;
    esac
done

if [[ -z "$DESKTOP" ]]; then
    echo "ERROR: elige un escritorio — 'hyprland' o 'kde'."
    _usage
    exit 1
fi

# Build the list of source directories from the choice.
case "$DESKTOP" in
    hyprland) _profiles=(common hyprland) ;;
    kde)      _profiles=(common)          ;;
esac

SOURCE_DIRS=()
for p in "${_profiles[@]}"; do
    d="$DOTFILES_DIR/dots/$p/.config"
    [[ -d "$d" ]] || { echo "ERROR: profile not found: dots/$p/.config"; exit 1; }
    SOURCE_DIRS+=("$d")
done

# ------------------------------------------------------------------
# Upstream (end-4/dots-hyprland) graphical config
# ------------------------------------------------------------------
# The shell is not vendored in this repo. It lives in a cache clone that
# `setup upstream sync` rebuilds from overlay/hyprland/, so only our delta is
# versioned here.
#
# UPSTREAM_LINK is a whitelist, and that is the whole point: upstream also ships
# kitty, foot, fish, mpv, zshrc.d and starship.toml, and none of them may be
# linked or they would shadow the ones in dots/common/.
UPSTREAM_CACHE="${DOTFILES_UPSTREAM_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles/upstream}"
UPSTREAM_CONFIG="$UPSTREAM_CACHE/dots/.config"
UPSTREAM_LINK=(hypr fuzzel matugen Kvantum wlogout kde-material-you-colors)

# Quickshell takes its config name from the directory under ~/.config/quickshell,
# so this is what `qs -c <name>` refers to. Kept as upstream's `ii`: the shell is
# end-4's work and renaming it only ever cost us merge noise.
UPSTREAM_QS_SRC="quickshell/ii"
UPSTREAM_QS_NAME="ii"

USE_UPSTREAM=false
[[ "$DESKTOP" == "hyprland" ]] && USE_UPSTREAM=true

if [[ "$USE_UPSTREAM" == true && "$UNLINK" == false && ! -d "$UPSTREAM_CONFIG" ]]; then
    if [[ "$DRY_RUN" == true ]]; then
        echo "[dry-run] Falta el clon de upstream; se ejecutaría 'setup upstream sync'."
    else
        echo "No hay clon de upstream todavía. Ejecutando 'setup upstream sync'..."
        bash "$DOTFILES_DIR/cmd/lib/upstream.sh" sync
    fi
fi

echo "Escritorio: $DESKTOP   (perfiles: ${_profiles[*]})"
[[ "$USE_UPSTREAM" == true ]] && echo "Upstream:   $UPSTREAM_CACHE"
[[ "$DRY_RUN" == true ]] && echo "[dry-run] No changes will be made."

BACKUP_DIR="$TARGET_DIR/backup"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

mkdir -p "$TARGET_DIR"
[[ "$DRY_RUN" == false ]] && mkdir -p "$BACKUP_DIR"

# Process one entry. Args: display/backup name (slash-free), source path, target path.
process_entry() {
    local entry_name="$1"
    local source="$2"
    local target="$3"

    # --unlink mode: remove symlink and optionally restore backup
    if [[ "$UNLINK" == true ]]; then
        if [[ -L "$target" ]]; then
            local latest_backup
            latest_backup=$(ls -1t "$BACKUP_DIR/${entry_name}."* 2>/dev/null | head -n1 || true)
            if [[ "$DRY_RUN" == false ]]; then
                rm "$target"
                if [[ -n "$latest_backup" ]]; then
                    mv "$latest_backup" "$target"
                    # Remove the backup dir itself if now empty
                    rmdir "$BACKUP_DIR" 2>/dev/null || true
                fi
            fi
            if [[ -n "$latest_backup" ]]; then
                echo "[restored]  $entry_name  (from $(basename "$latest_backup"))"
            else
                echo "[unlinked]  $entry_name"
            fi
        fi
        return
    fi

    # Target does not exist at all: create symlink
    if [[ ! -e "$target" && ! -L "$target" ]]; then
        [[ "$DRY_RUN" == false ]] && ln -s "$source" "$target"
        echo "[linked]    $entry_name"
        return
    fi

    # Target is already a symlink
    if [[ -L "$target" ]]; then
        local current_target
        current_target="$(readlink "$target")"
        if [[ "$current_target" == "$source" ]]; then
            echo "[skipped]   $entry_name  (already correct)"
            return
        fi
        # Symlink points elsewhere: fix it
        if [[ "$DRY_RUN" == false ]]; then
            rm "$target"
            ln -s "$source" "$target"
        fi
        echo "[relinked]  $entry_name  (was -> $current_target)"
        return
    fi

    # Target exists as a real file/dir: move to backup dir then replace with symlink
    local backup="$BACKUP_DIR/${entry_name}.${TIMESTAMP}"
    if [[ "$DRY_RUN" == false ]]; then
        mv "$target" "$backup"
        ln -s "$source" "$target"
    fi
    echo "[backed up] $entry_name  → backup/${entry_name}.${TIMESTAMP}"
}

# Owned by the KDE profile (dots/kde/, managed by cmd/lib/kde.sh with copies).
# KConfig rewrites these at runtime and would clobber a symlink, so they must
# never be linked from here. See dots/kde/files.list.
KDE_OWNED=(kdeglobals dolphinrc)

# Directories that must stay REAL directories in ~/.config, with their contents
# symlinked file by file. Two reasons, one per entry:
#
#   systemd/user        holds runtime *.target.wants/ for enabled user services;
#                       hijacking the whole directory would hide them.
#   xdg-desktop-portal  Hyprland owns hyprland-portals.conf and KDE owns
#                       kde-portals.conf. If this were a directory symlink into
#                       the Hyprland profile, `setup kde apply` would write the
#                       KDE file straight into dots/hyprland/. Keeping the
#                       directory real lets both drop their own file side by side.
#   fish                Split across profiles: config.fish, functions/, conf.d/ and
#                       completions/ are in common, auto-Hypr.fish only in hyprland.
#                       As a plain directory entry the second profile's symlink would
#                       replace the first's, leaving whichever came last — which is
#                       exactly how the Hyprland profile once hid the whole shell
#                       config behind a directory holding a single file.
MERGE_DIRS=("systemd/user" "xdg-desktop-portal" "fish")

# Top-level names the main loop must skip, derived from MERGE_DIRS.
MERGE_TOPS=()
for _m in "${MERGE_DIRS[@]}"; do MERGE_TOPS+=("${_m%%/*}"); done

# An earlier version of this script symlinked xdg-desktop-portal as a whole
# directory. Turn any such leftover back into a real one before linking anything:
# `mkdir -p` silently succeeds on a symlink-to-directory, so every file below
# would end up written INTO the profile it points at. This runs regardless of the
# chosen desktop — with kde the directory is not in any linked profile, but
# `setup kde apply` still has to drop kde-portals.conf into a real directory.
# Only the link is removed; whatever it pointed at is left untouched.
if [[ "$UNLINK" == false ]]; then
    for _rel in "${MERGE_DIRS[@]}"; do
        if [[ -L "$TARGET_DIR/$_rel" ]]; then
            echo "[fixed]     $_rel  (era un symlink a $(readlink "$TARGET_DIR/$_rel"))"
            [[ "$DRY_RUN" == false ]] && { rm "$TARGET_DIR/$_rel"; mkdir -p "$TARGET_DIR/$_rel"; }
        fi
    done
fi

for SOURCE_DIR in "${SOURCE_DIRS[@]}"; do
    shopt -s nullglob
    entries=("$SOURCE_DIR"/*)
    shopt -u nullglob

    if [[ ${#entries[@]} -eq 0 ]]; then
        echo "Nothing in $SOURCE_DIR yet."
        continue
    fi

    for entry_path in "${entries[@]}"; do
        entry_name="$(basename "$entry_path")"
        [[ "$entry_name" == ".gitkeep" ]] && continue
        # Handled file-by-file further down — see MERGE_DIRS.
        [[ " ${MERGE_TOPS[*]} " == *" $entry_name "* ]] && continue
        if [[ " ${KDE_OWNED[*]} " == *" $entry_name "* ]]; then
            echo "[kde]       $entry_name  (gestionado por 'setup kde')"
            continue
        fi
        process_entry "$entry_name" "$SOURCE_DIR/$entry_name" "$TARGET_DIR/$entry_name"
    done

    # Merge directories: keep the directory real, link each file inside it.
    for _rel in "${MERGE_DIRS[@]}"; do
        _src="$SOURCE_DIR/$_rel"
        [[ -d "$_src" ]] || continue
        [[ "$DRY_RUN" == false && "$UNLINK" == false ]] && mkdir -p "$TARGET_DIR/$_rel"
        shopt -s nullglob
        for _f in "$_src"/*; do
            _name="$(basename "$_f")"
            process_entry "$_name" "$_f" "$TARGET_DIR/$_rel/$_name"
        done
        shopt -u nullglob
    done
done

# Upstream entries, linked from the cache clone rather than from this repo.
if [[ "$USE_UPSTREAM" == true ]]; then
    if [[ ! -d "$UPSTREAM_CONFIG" && "$UNLINK" == false ]]; then
        echo "[skip]      upstream  (sin clon en $UPSTREAM_CACHE)"
    else
        for _name in "${UPSTREAM_LINK[@]}"; do
            [[ -e "$UPSTREAM_CONFIG/$_name" || "$UNLINK" == true ]] || continue
            process_entry "$_name" "$UPSTREAM_CONFIG/$_name" "$TARGET_DIR/$_name"
        done

        # ~/.config/quickshell stays a real directory so other quickshell configs
        # can live beside ours; only the `prism` entry inside it is ours.
        #
        # Earlier versions linked the whole directory into this repo. `mkdir -p`
        # silently succeeds on a symlink-to-directory, so leaving one in place
        # would create `prism` inside the repo instead of in ~/.config. Same
        # hazard the MERGE_DIRS fix above guards against.
        if [[ "$UNLINK" == false && -L "$TARGET_DIR/quickshell" ]]; then
            echo "[fixed]     quickshell  (era un symlink a $(readlink "$TARGET_DIR/quickshell"))"
            [[ "$DRY_RUN" == false ]] && rm "$TARGET_DIR/quickshell"
        fi
        [[ "$DRY_RUN" == false && "$UNLINK" == false ]] && mkdir -p "$TARGET_DIR/quickshell"
        process_entry "$UPSTREAM_QS_NAME" "$UPSTREAM_CONFIG/$UPSTREAM_QS_SRC" \
            "$TARGET_DIR/quickshell/$UPSTREAM_QS_NAME"

        # xdg-desktop-portal is a MERGE_DIR: Hyprland's file has to sit next to
        # whatever KDE writes, so link it file by file.
        if [[ -d "$UPSTREAM_CONFIG/xdg-desktop-portal" ]]; then
            [[ "$DRY_RUN" == false && "$UNLINK" == false ]] && mkdir -p "$TARGET_DIR/xdg-desktop-portal"
            shopt -s nullglob
            for _f in "$UPSTREAM_CONFIG"/xdg-desktop-portal/*; do
                _n="$(basename "$_f")"
                process_entry "$_n" "$_f" "$TARGET_DIR/xdg-desktop-portal/$_n"
            done
            shopt -u nullglob
        fi
    fi
fi

echo ""
if [[ "$DRY_RUN" == true ]]; then
    echo "Dry run complete. No changes were made."
elif [[ "$UNLINK" == true ]]; then
    echo "Unlink complete."
else
    echo "Symlinks up to date."
    [[ "$DESKTOP" == "kde" ]] && echo "Siguiente paso: ./setup kde apply"
fi
