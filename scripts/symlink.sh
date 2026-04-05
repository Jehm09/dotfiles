#!/usr/bin/env bash
# Dynamic dotfiles symlink manager.
#
# Reads every entry (file or directory) inside dots/.config/ and creates a
# matching symlink in ~/.config/. Adding a new app config is as simple as
# dropping its folder into dots/.config/ and re-running this script.
#
# Usage:
#   ./scripts/symlink.sh             Create / update all symlinks
#   ./scripts/symlink.sh --dry-run   Preview what would happen, no changes made
#   ./scripts/symlink.sh --unlink    Remove managed symlinks (restore backups if any)

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(dirname "$SCRIPT_DIR")"
SOURCE_DIR="$DOTFILES_DIR/dots/.config"
TARGET_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"

DRY_RUN=false
UNLINK=false

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=true ;;
        --unlink)  UNLINK=true  ;;
    esac
done

if [[ ! -d "$SOURCE_DIR" ]]; then
    echo "ERROR: Source directory not found: $SOURCE_DIR"
    exit 1
fi

[[ "$DRY_RUN" == true ]] && echo "[dry-run] No changes will be made."

mkdir -p "$TARGET_DIR"

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

# Process one entry from dots/.config/
process_entry() {
    local entry_name="$1"
    local source="$SOURCE_DIR/$entry_name"
    local target="$TARGET_DIR/$entry_name"

    # --unlink mode: remove symlink and optionally restore backup
    if [[ "$UNLINK" == true ]]; then
        if [[ -L "$target" ]]; then
            local latest_backup
            latest_backup=$(ls -1t "${target}.backup."* 2>/dev/null | head -n1 || true)
            if [[ "$DRY_RUN" == false ]]; then
                rm "$target"
                [[ -n "$latest_backup" ]] && mv "$latest_backup" "$target"
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

    # Target exists as a real file/dir: back it up then replace with symlink
    local backup="${target}.backup.${TIMESTAMP}"
    if [[ "$DRY_RUN" == false ]]; then
        mv "$target" "$backup"
        ln -s "$source" "$target"
    fi
    echo "[backed up] $entry_name  (backup: $(basename "$backup"))"
}

# Iterate all entries in dots/.config/ (both files and directories)
shopt -s nullglob
entries=("$SOURCE_DIR"/*)
shopt -u nullglob

if [[ ${#entries[@]} -eq 0 ]]; then
    echo "Nothing in $SOURCE_DIR yet."
    exit 0
fi

for entry_path in "${entries[@]}"; do
    entry_name="$(basename "$entry_path")"
    [[ "$entry_name" == ".gitkeep" ]] && continue
    process_entry "$entry_name"
done

echo ""
[[ "$DRY_RUN" == true ]] && echo "Dry run complete. No changes were made."
[[ "$DRY_RUN" == false && "$UNLINK" == false ]] && echo "Symlinks up to date."
[[ "$UNLINK" == true ]] && echo "Unlink complete."
