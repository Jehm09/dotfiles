#!/usr/bin/env bash
# Dynamic dotfiles symlink manager.
#
# Reads every entry (file or directory) inside dots/.config/ and creates a
# matching symlink in ~/.config/. Adding a new app config is as simple as
# dropping its folder into dots/.config/ and re-running this script.
#
# Usage:
#   ./cmd/lib/symlink.sh             Create / update all symlinks
#   ./cmd/lib/symlink.sh --dry-run   Preview what would happen, no changes made
#   ./cmd/lib/symlink.sh --unlink    Remove managed symlinks (restore backups if any)

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
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

BACKUP_DIR="$TARGET_DIR/backup"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

mkdir -p "$TARGET_DIR"
[[ "$DRY_RUN" == false ]] && mkdir -p "$BACKUP_DIR"

# Process one entry from dots/.config/
process_entry() {
    local entry_name="$1"
    local source="$SOURCE_DIR/$entry_name"
    local target="$TARGET_DIR/$entry_name"

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
if [[ "$DRY_RUN" == true ]]; then
    echo "Dry run complete. No changes were made."
elif [[ "$UNLINK" == true ]]; then
    echo "Unlink complete."
else
    echo "Symlinks up to date."
fi
