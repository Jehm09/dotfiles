#!/usr/bin/env bash
# Upstream overlay manager.
#
# Keeps end-4/dots-hyprland out of this repository. The upstream tree is cloned
# into a cache directory outside git; this repo stores only our delta:
#
#   overlay/hyprland/upstream.lock   url + commit the overlay applies to
#   overlay/hyprland/remove.list     upstream paths we delete
#   overlay/hyprland/local.ignore    per-machine paths, never exported
#   overlay/hyprland/files/          files that are entirely ours
#   overlay/hyprland/patches/        edits on top of upstream files
#
# Overlay paths are relative to the upstream repository root, so the patches
# apply with plain `git apply` and need no path rewriting.
#
# The cache clone carries two branches:
#   base   the locked upstream commit, untouched
#   mine   base + overlay applied  <- this is what gets symlinked into ~/.config
#
# Because `mine` descends from a real upstream commit, `update` is a genuine
# three-way merge: conflicts can only appear in files we actually patched.
#
# Usage:
#   setup upstream sync              Clone/checkout and rebuild `mine` from the overlay
#   setup upstream apply             Rebuild `mine` only (after editing patches by hand)
#   setup upstream update [--to REF] Fetch and merge upstream into `mine`
#   setup upstream export            Regenerate the overlay from `mine`
#   setup upstream deps              Build quickshell at the commit upstream pins
#   setup upstream status            Show lock, drift and pending changes

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$DOTFILES_DIR/cmd/lib/utils.sh"

OVERLAY_DIR="$DOTFILES_DIR/overlay/hyprland"
LOCK_FILE="$OVERLAY_DIR/upstream.lock"
REMOVE_LIST="$OVERLAY_DIR/remove.list"
IGNORE_FILE="$OVERLAY_DIR/local.ignore"
FILES_DIR="$OVERLAY_DIR/files"
PATCHES_DIR="$OVERLAY_DIR/patches"

CACHE_DIR="${DOTFILES_UPSTREAM_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles/upstream}"
DEFAULT_URL="https://github.com/end-4/dots-hyprland.git"

# Only this prefix of the upstream repo is ours to care about. Everything else
# (setup, sdata, dots-extra, licenses) stays upstream's business.
TRACKED_PREFIX="dots/.config"

# Upstream vendors this as a git submodule; it must come from `git submodule
# update`, never from our overlay.
SUBMODULE_PATH="dots/.config/quickshell/ii/modules/common/widgets/shapes"

BASE_BRANCH="base"
MINE_BRANCH="mine"

# ------------------------------------------------------------------
# Lock file
# ------------------------------------------------------------------
_lock_get() {
    [[ -f "$LOCK_FILE" ]] || return 1
    local v
    v="$(awk -F= -v k="$1" '$1==k {print $2; exit}' "$LOCK_FILE")"
    [[ -n "$v" ]] && echo "$v"
}

_lock_set() {
    mkdir -p "$OVERLAY_DIR"
    cat >"$LOCK_FILE" <<EOF
# Upstream commit this overlay applies to. Managed by 'setup upstream export'.
url=$1
commit=$2
EOF
}

_upstream_url() { _lock_get url || echo "$DEFAULT_URL"; }

# ------------------------------------------------------------------
# Path filtering
# ------------------------------------------------------------------
# A path is ignored when it is the submodule, lives inside it, or matches a
# glob in local.ignore (machine-specific files such as generated monitor
# layouts, which must never travel in the repo).
_is_ignored() {
    local path="$1" pattern
    [[ "$path" == "$SUBMODULE_PATH" || "$path" == "$SUBMODULE_PATH"/* ]] && return 0
    [[ -f "$IGNORE_FILE" ]] || return 1
    while read -r pattern; do
        [[ -z "$pattern" || "$pattern" == \#* ]] && continue
        # shellcheck disable=SC2053  # glob match is intentional
        [[ "$path" == $pattern ]] && return 0
    done <"$IGNORE_FILE"
    return 1
}

# ------------------------------------------------------------------
# Clone management
# ------------------------------------------------------------------
_ensure_clone() {
    local url
    url="$(_upstream_url)"

    if [[ ! -d "$CACHE_DIR/.git" ]]; then
        info "Cloning upstream into $CACHE_DIR"
        mkdir -p "$(dirname "$CACHE_DIR")"
        git clone "$url" "$CACHE_DIR"
    fi

    git -C "$CACHE_DIR" remote set-url origin "$url"
}

_require_clone() {
    [[ -d "$CACHE_DIR/.git" ]] || {
        error "No upstream clone at $CACHE_DIR"
        error "Run 'setup upstream sync' first."
        exit 1
    }
}

# Newest upstream commit already contained in `mine`. Before a merge this is the
# locked base; after one it is the upstream tip that was merged in. Either way it
# is the correct thing to diff our delta against, and to record in the lock.
#
# `update` records the ref it merged, because deriving this from `origin/main`
# alone is wrong whenever --to named something else: the export would then
# anchor to the old base and bake upstream's own changes into our patches.
_ANCHOR_FILE_REL=".git/dotfiles-upstream-anchor"

_upstream_tip() {
    local anchor="$CACHE_DIR/$_ANCHOR_FILE_REL" candidate
    if [[ -f "$anchor" ]]; then
        candidate="$(cat "$anchor")"
        # A stale anchor from an aborted merge is not an ancestor of `mine`;
        # ignoring it makes the fallback self-correcting.
        if git -C "$CACHE_DIR" merge-base --is-ancestor "$candidate" "$MINE_BRANCH" 2>/dev/null; then
            echo "$candidate"
            return
        fi
    fi
    git -C "$CACHE_DIR" merge-base origin/main "$MINE_BRANCH"
}

# ------------------------------------------------------------------
# Per-machine files
# ------------------------------------------------------------------
# Files matching local.ignore are deliberately absent from the overlay, so a
# rebuild would otherwise delete them — and they are generated once (monitor
# layout, workspace rules) and read by the config from then on. Carry them
# across the rebuild instead.
_stash_local_files() {
    local dest="$1" pattern f rel
    [[ -f "$IGNORE_FILE" ]] || return 0
    while read -r pattern; do
        [[ -z "$pattern" || "$pattern" == \#* ]] && continue
        # shellcheck disable=SC2231  # unquoted glob expansion is intentional
        for f in "$CACHE_DIR"/$pattern; do
            [[ -f "$f" ]] || continue
            rel="${f#"$CACHE_DIR"/}"
            mkdir -p "$dest/$(dirname "$rel")"
            cp -p "$f" "$dest/$rel"
        done
    done <"$IGNORE_FILE"
}

# Mirror local.ignore into the clone's exclude file. Keeping these paths
# untracked is what actually protects them: a stash/restore only spans one
# rebuild, whereas any plain `git checkout` would delete tracked copies.
_sync_git_exclude() {
    local exclude="$CACHE_DIR/.git/info/exclude"
    mkdir -p "$(dirname "$exclude")"
    {
        echo "# Generated from overlay/hyprland/local.ignore by 'setup upstream'."
        if [[ -f "$IGNORE_FILE" ]]; then
            grep -v '^[[:space:]]*#' "$IGNORE_FILE" | grep -v '^[[:space:]]*$' | sed 's|^|/|'
        fi
    } >"$exclude"
}

_unstash_local_files() {
    local src="$1" f rel n=0
    [[ -d "$src" ]] || return 0
    while IFS= read -r -d '' f; do
        rel="${f#"$src"/}"
        mkdir -p "$(dirname "$CACHE_DIR/$rel")"
        cp -p "$f" "$CACHE_DIR/$rel"
        n=$((n + 1))
    done < <(find "$src" -type f -print0)
    ((n)) && info "Preserved $n per-machine file(s)"
    return 0
}

# ------------------------------------------------------------------
# apply — rebuild `mine` from base + overlay
# ------------------------------------------------------------------
_apply_overlay() {
    local commit
    commit="$(_lock_get commit)" || { error "No commit in $LOCK_FILE"; exit 1; }

    _sync_git_exclude

    local stash
    stash="$(mktemp -d)"
    _stash_local_files "$stash"

    info "Checking out base at ${commit:0:8}"
    git -C "$CACHE_DIR" checkout -q -B "$BASE_BRANCH" "$commit"
    git -C "$CACHE_DIR" submodule update --init --recursive -q

    info "Rebuilding '$MINE_BRANCH' from the overlay"
    git -C "$CACHE_DIR" checkout -q -B "$MINE_BRANCH" "$BASE_BRANCH"

    local n_removed=0 n_files=0 n_patched=0 failed=()

    # 1. deletions
    if [[ -f "$REMOVE_LIST" ]]; then
        while read -r path; do
            [[ -z "$path" || "$path" == \#* ]] && continue
            rm -rf "${CACHE_DIR:?}/$path"
            n_removed=$((n_removed + 1))
        done <"$REMOVE_LIST"
    fi

    # 2. our own files
    if [[ -d "$FILES_DIR" ]]; then
        while IFS= read -r -d '' src; do
            local rel="${src#"$FILES_DIR"/}"
            mkdir -p "$(dirname "$CACHE_DIR/$rel")"
            cp -p "$src" "$CACHE_DIR/$rel"
            n_files=$((n_files + 1))
        done < <(find "$FILES_DIR" -type f -print0)
    fi

    # 3. patches on upstream files. --3way leaves conflict markers instead of
    #    failing outright, so a drifted patch is inspectable rather than fatal.
    if [[ -d "$PATCHES_DIR" ]]; then
        while IFS= read -r -d '' patch; do
            if git -C "$CACHE_DIR" apply --3way --whitespace=nowarn "$patch" 2>/dev/null; then
                n_patched=$((n_patched + 1))
            else
                failed+=("${patch#"$PATCHES_DIR"/}")
            fi
        done < <(find "$PATCHES_DIR" -name '*.patch' -print0 | sort -z)
    fi

    _unstash_local_files "$stash"
    rm -rf "$stash"

    # Removing every file in a directory leaves the directory behind, since git
    # does not track empty ones. Prune them so the tree matches a clean build.
    find "$CACHE_DIR/$TRACKED_PREFIX" -mindepth 1 -type d -empty -delete 2>/dev/null || true

    git -C "$CACHE_DIR" add -A
    if git -C "$CACHE_DIR" diff --cached --quiet; then
        warn "Overlay produced no changes"
    else
        git -C "$CACHE_DIR" -c user.name=setup -c user.email=setup@localhost \
            commit -q -m "overlay: local changes"
    fi

    success "Applied: $n_removed removed, $n_files own files, $n_patched patches"

    if ((${#failed[@]})); then
        warn "${#failed[@]} patch(es) did not apply cleanly:"
        printf '      %s\n' "${failed[@]}"
        warn "Inspect the conflict markers in $CACHE_DIR, then run 'setup upstream export'."
        return 1
    fi
}

# ------------------------------------------------------------------
# Subcommands
# ------------------------------------------------------------------
cmd_sync() {
    [[ -f "$LOCK_FILE" ]] || { error "Missing $LOCK_FILE"; exit 1; }
    _ensure_clone
    info "Fetching upstream"
    git -C "$CACHE_DIR" fetch -q origin
    _apply_overlay
    success "Upstream tree ready at $CACHE_DIR"
}

cmd_apply() {
    _require_clone
    _apply_overlay
}

cmd_update() {
    local target="origin/main"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --to) target="$2"; shift 2 ;;
            *) error "Unknown option: $1"; exit 1 ;;
        esac
    done

    _require_clone
    info "Fetching upstream"
    git -C "$CACHE_DIR" fetch -q origin

    git -C "$CACHE_DIR" checkout -q "$MINE_BRANCH"
    if ! git -C "$CACHE_DIR" diff --quiet || ! git -C "$CACHE_DIR" diff --cached --quiet; then
        error "The clone has uncommitted changes."
        error "Run 'setup upstream export' to save them, or discard them with:"
        error "  git -C $CACHE_DIR checkout ."
        exit 1
    fi

    git -C "$CACHE_DIR" rev-parse --verify "$target^{commit}" \
        >"$CACHE_DIR/$_ANCHOR_FILE_REL"

    info "Merging $target into $MINE_BRANCH"
    if git -C "$CACHE_DIR" -c user.name=setup -c user.email=setup@localhost \
        merge --no-edit "$target"; then
        git -C "$CACHE_DIR" submodule update --init --recursive -q
        success "Merged cleanly. Now run: setup upstream export"
    else
        echo
        warn "Merge conflicts in:"
        git -C "$CACHE_DIR" diff --name-only --diff-filter=U | sed 's/^/      /'
        echo
        info "Resolve them in $CACHE_DIR, then:"
        info "  git -C $CACHE_DIR add <files> && git -C $CACHE_DIR merge --continue"
        info "  setup upstream export"
        info "Or give up on this update with:"
        info "  git -C $CACHE_DIR merge --abort"
        return 1
    fi
}

cmd_export() {
    _require_clone
    git -C "$CACHE_DIR" checkout -q "$MINE_BRANCH"

    local tip
    tip="$(_upstream_tip)"

    # Fold any live edits (files symlinked into ~/.config are edited in place
    # here) into `mine` before diffing.
    git -C "$CACHE_DIR" add -A
    if ! git -C "$CACHE_DIR" diff --cached --quiet; then
        info "Committing live edits from the clone"
        git -C "$CACHE_DIR" -c user.name=setup -c user.email=setup@localhost \
            commit -q -m "overlay: live edits"
    fi

    info "Exporting delta against ${tip:0:8}"
    rm -rf "$FILES_DIR" "$PATCHES_DIR"
    mkdir -p "$FILES_DIR" "$PATCHES_DIR"
    : >"$REMOVE_LIST.tmp"

    local n_add=0 n_mod=0 n_del=0 status path
    while IFS=$'\t' read -r status path; do
        _is_ignored "$path" && continue
        case "${status:0:1}" in
            A)
                mkdir -p "$(dirname "$FILES_DIR/$path")"
                git -C "$CACHE_DIR" show "$MINE_BRANCH:$path" >"$FILES_DIR/$path"
                n_add=$((n_add + 1))
                ;;
            M|T)
                mkdir -p "$(dirname "$PATCHES_DIR/$path")"
                git -C "$CACHE_DIR" diff "$tip" "$MINE_BRANCH" -- "$path" \
                    >"$PATCHES_DIR/$path.patch"
                n_mod=$((n_mod + 1))
                ;;
            D)
                echo "$path" >>"$REMOVE_LIST.tmp"
                n_del=$((n_del + 1))
                ;;
        esac
    done < <(git -C "$CACHE_DIR" diff --name-status --no-renames \
                 "$tip" "$MINE_BRANCH" -- "$TRACKED_PREFIX")

    {
        echo "# Upstream paths removed by this overlay."
        echo "# Managed by 'setup upstream export'."
        sort "$REMOVE_LIST.tmp"
    } >"$REMOVE_LIST"
    rm -f "$REMOVE_LIST.tmp"

    # Restore file modes; git show does not carry the executable bit.
    while IFS= read -r -d '' f; do
        local rel="${f#"$FILES_DIR"/}"
        if [[ "$(git -C "$CACHE_DIR" ls-tree "$MINE_BRANCH" -- "$rel" | awk '{print $1}')" == "100755" ]]; then
            chmod +x "$f"
        fi
    done < <(find "$FILES_DIR" -type f -print0)

    _lock_set "$(_upstream_url)" "$tip"

    success "Exported: $n_add own files, $n_mod patches, $n_del removals"
    info "Lock now at ${tip:0:8} — commit overlay/ to record it."
}

cmd_deps() {
    _require_clone
    prevent_root

    local pkgdir="$CACHE_DIR/sdata/dist-arch/illogical-impulse-quickshell-git"
    [[ -d "$pkgdir" ]] || { error "Not found: $pkgdir"; exit 1; }

    local pinned
    pinned="$(awk -F"'" '/^_commit=/ {print $2; exit}' "$pkgdir/PKGBUILD")"
    info "Upstream pins quickshell at ${pinned:0:8}"

    # The metapackage declares conflicts=(quickshell quickshell-git), so the AUR
    # build has to be removed before this one can be installed. Build first and
    # swap at the end: there is usually no cached package to roll back to, so a
    # build that fails after the removal would leave the desktop with no shell.
    info "Building illogical-impulse-quickshell-git (the running shell is untouched)"
    ( cd "$pkgdir" && makepkg -Afs --noconfirm )

    local built
    built="$(cd "$pkgdir" && makepkg --packagelist 2>/dev/null | head -1)"
    if [[ -z "$built" || ! -f "$built" ]]; then
        error "Build produced no package. Nothing was changed."
        exit 1
    fi
    success "Built $(basename "$built")"

    if pacman -Qq quickshell-git &>/dev/null; then
        info "Removing the unpinned AUR build"
        sudo pacman -Rdd --noconfirm quickshell-git
    fi
    sudo pacman -U --noconfirm "$built"

    success "quickshell pinned at ${pinned:0:8}"
    info "Restart the shell to pick it up:  qs -c prism"
}

cmd_status() {
    local commit url
    url="$(_upstream_url)"
    commit="$(_lock_get commit || echo '(none)')"

    echo
    echo -e "  ${_CLR_BOLD}Upstream${_CLR_RST}  $url"
    echo -e "  ${_CLR_BOLD}Locked${_CLR_RST}    ${commit:0:12}"
    echo -e "  ${_CLR_BOLD}Cache${_CLR_RST}     $CACHE_DIR"
    echo

    if [[ ! -d "$CACHE_DIR/.git" ]]; then
        warn "No clone yet. Run 'setup upstream sync'."
        return 0
    fi

    local behind
    behind="$(git -C "$CACHE_DIR" rev-list --count "$commit..origin/main" 2>/dev/null || echo '?')"
    if [[ "$behind" == "0" ]]; then
        success "Up to date with origin/main"
    else
        info "$behind upstream commit(s) not merged yet — run 'setup upstream update'"
    fi

    if git -C "$CACHE_DIR" diff --quiet && git -C "$CACHE_DIR" diff --cached --quiet; then
        success "Clone is clean"
    else
        warn "Clone has uncommitted edits — run 'setup upstream export'"
        git -C "$CACHE_DIR" status --short | sed 's/^/      /'
    fi

    if command -v pacman &>/dev/null; then
        local pinned
        pinned="$(awk -F"'" '/^_commit=/ {print $2; exit}' \
            "$CACHE_DIR/sdata/dist-arch/illogical-impulse-quickshell-git/PKGBUILD" 2>/dev/null || true)"
        if pacman -Qq illogical-impulse-quickshell-git &>/dev/null; then
            success "quickshell: pinned build installed (upstream pins ${pinned:0:8})"
        elif pacman -Qq quickshell-git &>/dev/null; then
            warn "quickshell: unpinned AUR build installed — 'yay -Syu' can break the shell"
            warn "            run 'setup upstream deps' to switch to the pinned one"
        fi
    fi
    echo
}

_usage() {
    cat <<EOF

Usage: setup upstream <subcommand>

    sync              Clone/fetch upstream, check out the locked commit and
                      rebuild the working tree from the overlay
    apply             Rebuild the working tree only (after editing patches)
    update [--to REF] Fetch and merge upstream; stops on conflicts
    export            Regenerate overlay/ and upstream.lock from the clone
    deps              Build quickshell at the commit upstream pins
    status            Show lock, drift and pending changes

Typical update:
    setup upstream update
    # resolve conflicts if any
    setup upstream export
    git add overlay && git commit

EOF
}

case "${1:-}" in
    sync)   shift; cmd_sync   "$@" ;;
    apply)  shift; cmd_apply  "$@" ;;
    update) shift; cmd_update "$@" ;;
    export) shift; cmd_export "$@" ;;
    deps)   shift; cmd_deps   "$@" ;;
    status) shift; cmd_status "$@" ;;
    -h|--help|help|"") _usage ;;
    *) error "Unknown subcommand: $1"; _usage; exit 1 ;;
esac
