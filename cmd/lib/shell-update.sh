#!/usr/bin/env bash
#
# shell-update.sh — the whole end-4 update as one run, for the "Update" page in
# quickshell settings (which opens it in a terminal so sudo can ask).
#
#   setup update shell            save local edits → merge end-4 → export →
#                                 commit overlay/ → rebuild the pinned runtime →
#                                 restart the bar if quickshell changed → push
#   setup update shell --status   JSON snapshot for the settings page. Changes
#                                 nothing beyond a `git fetch` in the clone.
#
# A merge conflict is aborted on the spot. ~/.config/hypr and quickshell read
# the clone live, so conflict markers left in it break the running session; the
# clashing files are reported instead and everything stays as it was.
#
# Progress goes to $STATE_FILE (read by the settings page) and the full output
# to a log under $STATE_DIR/logs.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$DOTFILES_DIR/cmd/lib/utils.sh"

SETUP="$DOTFILES_DIR/setup"
CLONE="${DOTFILES_UPSTREAM_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles/upstream}"
PKGBUILD="$CLONE/sdata/dist-arch/illogical-impulse-quickshell-git/PKGBUILD"
PIN_FILE="$CLONE/.git/dotfiles-quickshell-pin"
LOCK_FILE="$DOTFILES_DIR/overlay/hyprland/upstream.lock"
RUNTIME_PKG="illogical-impulse-quickshell-git"
# Settings rewrites it on every change; Joe wants it committed whatever its state.
SETTINGS_JSON="dots/hyprland/.config/settings/quickshell/config.json"

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles"
STATE_FILE="$STATE_DIR/shell-update.json"
RUN_LOCK="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/dotfiles-shell-update.lock"

_started=""
_log=""
_step=""

# ------------------------------------------------------------------
# Small readers
# ------------------------------------------------------------------
_pinned()          { awk -F"'" '/^_commit=/ {print $2; exit}' "$PKGBUILD" 2>/dev/null || true; }
_locked()          { awk -F= '$1=="commit" {print $2; exit}' "$LOCK_FILE" 2>/dev/null || true; }
_installed_pin()   { cat "$PIN_FILE" 2>/dev/null || true; }
_installed_date()  { LC_ALL=C pacman -Qi "$RUNTIME_PKG" 2>/dev/null | awk -F': ' '/^Install Date/ {print $2; exit}' || true; }
_abi_ok() {
    command -v quickshell &>/dev/null || return 0
    quickshell --private-check-compat &>/dev/null
}

# ------------------------------------------------------------------
# State file + notifications
# ------------------------------------------------------------------
_state() {   # _state <state> <message> [file...]
    local state="$1" message="$2" finished=""
    shift 2
    [[ "$state" != running ]] && finished="$(date -Iseconds)"
    mkdir -p "$STATE_DIR"
    jq -n --arg state "$state" --arg step "$_step" --arg message "$message" \
        --arg started "$_started" --arg finished "$finished" --arg log "$_log" \
        '{state: $state, step: $step, message: $message, files: $ARGS.positional,
          started: $started, finished: $finished, log: $log}' \
        --args "$@" >"$STATE_FILE.tmp"
    mv "$STATE_FILE.tmp" "$STATE_FILE"
}

_notify() {
    command -v notify-send &>/dev/null || return 0
    notify-send -a "Dotfiles" "$1" "$2" 2>/dev/null || true
}

_phase() {
    _step="$1"
    step "$1"
    _state running "$1"
}

# A known failure: record why, tell the user, stop.
_fail_msg() {
    trap - ERR
    error "$1"
    _state error "$1"
    _notify "end-4 update failed" "$1"
    exit 1
}

# Anything else that breaks under set -e lands here.
_fail_unexpected() {
    local rc=$?
    trap - ERR
    local msg="Failed during '$_step' (exit $rc). See the log: $_log"
    error "$msg"
    _state error "$msg"
    _notify "end-4 update failed" "$msg"
    exit "$rc"
}

# ------------------------------------------------------------------
# Steps
# ------------------------------------------------------------------
_preflight() {
    [[ -d "$CLONE/.git" ]] \
        || _fail_msg "No upstream clone at $CLONE — run 'setup upstream sync' first."
    if [[ -f "$CLONE/.git/MERGE_HEAD" ]]; then
        _fail_msg "The clone has a merge in progress. Finish it or run: git -C $CLONE merge --abort"
    fi

    local branch gitdir
    branch="$(git -C "$DOTFILES_DIR" symbolic-ref --short -q HEAD || true)"
    [[ "$branch" == main ]] \
        || _fail_msg "The dotfiles repo is on '${branch:-a detached HEAD}', not main."
    gitdir="$(git -C "$DOTFILES_DIR" rev-parse --absolute-git-dir)"
    if [[ -f "$gitdir/MERGE_HEAD" || -d "$gitdir/rebase-merge" || -d "$gitdir/rebase-apply" ]]; then
        _fail_msg "The dotfiles repo has a merge or rebase in progress."
    fi

    info "Syncing the dotfiles repo with origin"
    git -C "$DOTFILES_DIR" fetch -q origin \
        || _fail_msg "git fetch of the dotfiles repo failed (network or SSH key?)."
    git -C "$DOTFILES_DIR" merge -q --ff-only origin/main \
        || _fail_msg "main cannot fast-forward to origin/main (diverged, or local edits in the way). Reconcile it by hand."
    success "Dotfiles repo is on main and up to date with origin"
}

# Commits only the given paths — `git commit -- <path>` leaves anything else
# staged or modified in the repo (fish_variables...) out of it.
_commit_paths() {   # _commit_paths <message> <path...>
    local message="$1"
    shift
    if [[ -z "$(git -C "$DOTFILES_DIR" status --porcelain -- "$@")" ]]; then
        success "$* unchanged — nothing to commit"
        return 0
    fi
    git -C "$DOTFILES_DIR" add -A -- "$@"
    git -C "$DOTFILES_DIR" commit -q -m "$message" -- "$@"
    success "Committed: $message"
}

_abort_conflict() {
    local files=()
    mapfile -t files < <(git -C "$CLONE" diff --name-only --diff-filter=U)
    git -C "$CLONE" merge --abort

    local msg="end-4 changed ${#files[@]} file(s) you also patch. The merge was aborted; nothing changed."
    echo
    warn "$msg"
    printf '      %s\n' "${files[@]}"
    info "To merge by hand:  $SETUP upstream update   (fix the markers, then"
    info "git -C $CLONE add <files> && git -C $CLONE merge --continue, then $SETUP upstream export)"
    _state conflict "$msg" "${files[@]}"
    _notify "end-4 update: conflicts" "$msg"
    exit 2
}

# Only the bar (config ii); the settings window is another instance (-p settings.qml).
# The crash-handler variables are dropped for the same reason as QsLaunch.qml,
# and fd 9 (the run lock) is closed so the new bar does not keep holding it.
_restart_bar() {
    if ! qs list --all 2>/dev/null | grep -q "quickshell/ii/shell.qml"; then
        info "The bar is not running — nothing to restart"
        return 0
    fi
    qs kill -c ii 9>&- >/dev/null 2>&1 || true
    sleep 1
    env -u __QUICKSHELL_CRASH_INFO_FD -u __QUICKSHELL_CRASH_DUMP_PID -u __QUICKSHELL_CRASH_SIGNAL \
        setsid -f qs -c ii >/dev/null 2>&1 </dev/null 9>&-
    success "Bar restarted on the new quickshell"
}

_push() {
    local ahead
    ahead="$(git -C "$DOTFILES_DIR" rev-list --count origin/main..main)"
    if ((ahead == 0)); then
        success "Nothing to push"
        return 0
    fi
    git -C "$DOTFILES_DIR" push -q origin main \
        || _fail_msg "git push failed. The $ahead commit(s) are saved locally; push them with: git -C $DOTFILES_DIR push"
    success "Pushed $ahead commit(s) to origin/main"
}

# ------------------------------------------------------------------
# Commands
# ------------------------------------------------------------------
cmd_run() {
    mkdir -p "$STATE_DIR/logs"
    exec 9>"$RUN_LOCK"
    flock -n 9 || { error "Another end-4 update is already running."; exit 1; }

    _started="$(date -Iseconds)"
    _log="$STATE_DIR/logs/shell-update-$(date +%Y%m%d-%H%M%S).log"
    exec > >(tee -a "$_log") 2>&1
    trap _fail_unexpected ERR

    _phase "Preflight"
    _preflight

    _phase "Save local edits"
    if [[ -n "$(git -C "$CLONE" status --porcelain)" ]]; then
        "$SETUP" upstream export
        _commit_paths "chore(overlay): guardar cambios locales antes de actualizar end-4" overlay
    else
        success "No local edits in the clone"
    fi
    _commit_paths "chore(settings): guardar config de quickshell" "$SETTINGS_JSON"

    _phase "Merge end-4"
    if ! "$SETUP" upstream update; then
        [[ -f "$CLONE/.git/MERGE_HEAD" ]] && _abort_conflict
        _fail_msg "Merging end-4 failed, and not because of a conflict. See the log: $_log"
    fi

    _phase "Export overlay"
    "$SETUP" upstream export
    local locked pinned
    locked="$(_locked)"
    pinned="$(_pinned)"
    _commit_paths "chore(upstream): actualizar end-4 a ${locked:0:7} (quickshell ${pinned:0:7})" overlay

    _phase "Runtime (quickshell)"
    local before after
    before="$(_installed_date)"
    "$SETUP" upstream deps
    after="$(_installed_date)"

    if [[ "$before" != "$after" ]]; then
        _phase "Restart bar"
        _restart_bar
    fi

    _phase "Push"
    _push

    _step="Done"
    local msg="end-4 at ${locked:0:7}, quickshell at ${pinned:0:7}."
    _state ok "$msg"
    step "Done"
    success "$msg"
    _notify "end-4 update finished" "$msg"
}

cmd_status() {
    if [[ ! -d "$CLONE/.git" ]]; then
        jq -n --arg repo "$DOTFILES_DIR" --arg clone "$CLONE" \
            '{ok: false, error: "No upstream clone — run setup upstream sync", repo: $repo, clone: $clone}'
        return 0
    fi

    local fetched=true merging=false dirty=false abi=true running=false behind head
    # The state file alone says "running" forever if the terminal was closed mid-run;
    # the lock is only held while a run is actually alive.
    if [[ -e "$RUN_LOCK" ]] && ! flock -n "$RUN_LOCK" true; then running=true; fi
    timeout 30 git -C "$CLONE" fetch -q origin 2>/dev/null || fetched=false
    behind="$(git -C "$CLONE" rev-list --count mine..origin/main 2>/dev/null || echo 0)"
    head="$(git -C "$CLONE" rev-parse --short=7 origin/main 2>/dev/null || true)"
    [[ -f "$CLONE/.git/MERGE_HEAD" ]] && merging=true
    [[ -n "$(git -C "$CLONE" status --porcelain 2>/dev/null)" ]] && dirty=true
    _abi_ok || abi=false

    jq -n --arg repo "$DOTFILES_DIR" --arg clone "$CLONE" \
        --arg locked "$(_locked)" --arg upstreamHead "$head" --argjson behind "$behind" \
        --argjson fetched "$fetched" --argjson dirty "$dirty" --argjson merging "$merging" \
        --arg pinned "$(_pinned)" --arg installedPin "$(_installed_pin)" \
        --arg installedVersion "$(pacman -Q "$RUNTIME_PKG" 2>/dev/null | awk '{print $2}' || true)" \
        --argjson abiOk "$abi" --argjson running "$running" \
        '{ok: true, running: $running, repo: $repo, clone: $clone, locked: $locked, upstreamHead: $upstreamHead,
          behind: $behind, fetched: $fetched, dirty: $dirty, merging: $merging,
          pinned: $pinned, installedPin: $installedPin, installedVersion: $installedVersion,
          abiOk: $abiOk,
          runtime: (if ($abiOk | not) then "abi"
                    elif $installedPin == "" then "untracked"
                    elif $pinned != $installedPin then "stale"
                    else "ok" end)}'
}

case "${1:-}" in
    --status) cmd_status ;;
    "")       cmd_run ;;
    *)        error "Unknown option: $1"; exit 1 ;;
esac
