#!/usr/bin/env bash
#
# update.sh — routine maintenance: everything that goes stale between installs.
#
# 'post' is for building the machine, 'update' is for keeping it alive. The work
# is split across four sources that drift independently, which is the whole
# reason this command exists — doing them in the wrong order wastes a Qt compile
# or leaves the shell unable to start:
#
#   1. system    the official repos and the AUR            pacman / yay
#   2. end-4     the upstream shell, merged into overlay/  setup upstream
#   3. runtime   quickshell, pinned to a commit by end-4   setup upstream deps
#   4. repo      the package lists in packages/*.conf      setup post --pkgs
#
# Order matters. A qt6-base bump in (1) breaks the runtime in (3) without moving
# the pin, and a merge in (2) can move that pin as well, so (3) always runs after
# both. Linking dotfiles runs last because a merge can add new files to link.
#
# Usage:
#   setup update check                     What is stale, changes nothing
#   setup update all --hyprland            The whole chain, in order
#   setup update system                    Repos + AUR only
#   setup update end4                      Merge upstream and export the overlay
#   setup update runtime [--force]         Rebuild/reinstall pinned quickshell
#   setup update pkgs --hyprland           Reinstall from packages/*.conf
#   setup update dotfiles --hyprland       Re-link ~/.config
#   setup update shell [--status]          end4 + commit + runtime + push in one
#                                          run (cmd/lib/shell-update.sh)

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$DOTFILES_DIR/cmd/lib/utils.sh"

SETUP="$DOTFILES_DIR/setup"

# Set by --hyprland/--kde. The steps that read packages/*.conf or link ~/.config
# need it; the rest do not, so it is validated per mode rather than up front.
_desktop=""
_passthru=()
_shell_args=()

_require_desktop() {
    [[ -n "$_desktop" ]] && return 0
    error "This step needs a desktop: pass --hyprland or --kde."
    error "See: setup update --help"
    exit 1
}

# The helper to drive the AUR with. Mirrors 'post': whichever is installed wins,
# and with neither this degrades to plain pacman instead of failing — the repos
# are the part that matters most and they need no helper.
_sync_all() {
    local h
    for h in paru yay; do
        if command -v "$h" &>/dev/null; then
            info "Updating repos and AUR with $h"
            "$h" -Syu
            return 0
        fi
    done
    warn "No AUR helper found — updating the official repos only."
    sudo pacman -Syu
}

# ------------------------------------------------------------------
# check — read-only dashboard
# ------------------------------------------------------------------
cmd_check() {
    step "System packages"
    if command -v checkupdates &>/dev/null; then
        local n
        n="$(checkupdates 2>/dev/null | wc -l)"
        if ((n)); then
            info "$n update(s) waiting in the official repos"
        else
            success "Official repos up to date"
        fi
    else
        info "checkupdates is not installed (pacman-contrib), so this cannot be"
        info "answered without hitting the network. 'setup update system' will."
    fi

    step "end-4 shell and runtime"
    "$SETUP" upstream status || true

    step "This repo"
    if git -C "$DOTFILES_DIR" diff --quiet && git -C "$DOTFILES_DIR" diff --cached --quiet; then
        success "Working tree is clean"
    else
        info "Uncommitted changes:"
        git -C "$DOTFILES_DIR" status --short | sed 's/^/      /'
    fi
    echo
}

# ------------------------------------------------------------------
# Individual steps
# ------------------------------------------------------------------
cmd_system() {
    step "1. System packages"
    _sync_all
}

cmd_end4() {
    step "2. end-4 upstream"
    # Both of these stop on their own if the merge conflicts or the clone is
    # dirty, and set -e turns that into a stop here rather than a half-update.
    "$SETUP" upstream update
    "$SETUP" upstream export

    # --porcelain, not diff --quiet: a merge that only adds files leaves them
    # untracked under overlay/, which diff does not see.
    if [[ -z "$(git -C "$DOTFILES_DIR" status --porcelain -- overlay)" ]]; then
        success "Overlay unchanged — nothing new from end-4"
        return 0
    fi
    info "The overlay changed. Review it, then commit:"
    info "    git -C $DOTFILES_DIR diff overlay"
    info "    git -C $DOTFILES_DIR add overlay && git commit -m 'upstream: merge end-4'"
}

cmd_runtime() {
    step "3. Pinned runtime (quickshell)"
    "$SETUP" upstream deps "${_passthru[@]}"
}

cmd_pkgs() {
    _require_desktop
    step "4. Packages from this repo"
    "$SETUP" post --pkgs "--$_desktop"
}

cmd_shell() {
    exec bash "$DOTFILES_DIR/cmd/lib/shell-update.sh" "${_shell_args[@]}"
}

cmd_dotfiles() {
    _require_desktop
    step "5. Dotfile symlinks"
    "$SETUP" post --only dotfiles "--$_desktop"
}

# ------------------------------------------------------------------
# all — the whole chain, in the order the header explains
# ------------------------------------------------------------------
cmd_all() {
    _require_desktop
    cmd_system
    cmd_end4
    cmd_runtime
    cmd_pkgs
    cmd_dotfiles

    step "Done"
    success "Everything is up to date."
    info "Reload the shell to pick it up:  hyprctl reload && qs -c ii"
}

_usage() {
    cat <<EOF

Usage: setup update <subcommand> [--hyprland|--kde]

Routine maintenance. 'post' builds the machine; this keeps it current.

    check             What is stale — changes nothing
    all               Everything below, in order (needs a desktop)
    system            Official repos + AUR
    end4              Merge end-4's changes and export the overlay
    runtime [--force] Reinstall the quickshell build end-4 pins
    pkgs              Reinstall from packages/*.conf (needs a desktop)
    dotfiles          Re-link ~/.config (needs a desktop)
    shell [--status]  end4 + commit overlay/ + runtime + push in one run, aborting
                      on merge conflicts (what the quickshell Update page runs).
                      --status prints a JSON snapshot and changes nothing

Why the order is fixed:

    A qt6-base upgrade in 'system' breaks the pinned quickshell without moving
    the pin, because quickshell links Qt's private API. A merge in 'end4' can
    move that pin too. So 'runtime' runs after both, and 'dotfiles' runs last
    because a merge can add new files that need linking.

'runtime' reuses an already-built package when one is newer than qt6-base, so it
only pays for a Qt compile when there is genuinely nothing to reuse. --force
skips that and always rebuilds.

EOF
}

# ------------------------------------------------------------------
# Flags. The desktop and --force can appear in any position, so they are
# stripped first and the remaining word is the subcommand.
# ------------------------------------------------------------------
_mode=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --hyprland) _desktop="hyprland" ;;
        --kde)      _desktop="kde"      ;;
        --force)    _passthru+=("--force") ;;
        --status)   _shell_args+=("--status") ;;
        -h|--help)  _usage; exit 0 ;;
        -*)         error "Unknown option: $1"; error "See: setup update --help"; exit 1 ;;
        *)
            if [[ -n "$_mode" ]]; then
                error "Only one subcommand at a time (got '$_mode' and '$1')."
                exit 1
            fi
            _mode="$1"
            ;;
    esac
    shift
done

case "$_mode" in
    check)     cmd_check    ;;
    all)       cmd_all      ;;
    system)    cmd_system   ;;
    end4)      cmd_end4     ;;
    runtime)   cmd_runtime  ;;
    pkgs)      cmd_pkgs     ;;
    dotfiles)  cmd_dotfiles ;;
    shell)     cmd_shell    ;;
    ""|help)   _usage       ;;
    *) error "Unknown subcommand: $_mode"; _usage; exit 1 ;;
esac
