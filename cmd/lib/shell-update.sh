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
# ~/.config/hypr and quickshell read the clone live, so the run never leaves it
# broken:
#   - a conflict is detected before touching the clone (merge-tree dry run); the
#     clashing files are reported and nothing changes.
#   - after a clean merge Hyprland is reloaded and checked, and the bar too. Any
#     failure from the merge until before the push (config errors, the bar dying,
#     export/deps failing) rolls the clone, the overlay commits and the runtime
#     back to where they were, and reloads the session on that version.
#
# Progress goes to $STATE_FILE (read by the settings page) and the full output
# to a log under $STATE_DIR/logs.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$DOTFILES_DIR/cmd/lib/utils.sh"
source "$DOTFILES_DIR/cmd/lib/run-common.sh"

SETUP="$DOTFILES_DIR/setup"
CLONE="${DOTFILES_UPSTREAM_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles/upstream}"
# quickshell is the only package end-4 pins to a commit; the rest follow pacman/yay.
PKGBUILD_REL="sdata/dist-arch/illogical-impulse-quickshell-git/PKGBUILD"
PKGBUILD="$CLONE/$PKGBUILD_REL"
PIN_FILE="$CLONE/.git/dotfiles-quickshell-pin"
LOCK_FILE="$DOTFILES_DIR/overlay/hyprland/upstream.lock"
RUNTIME_PKG="illogical-impulse-quickshell-git"
# Settings rewrites it on every change; Joe wants it committed whatever its state.
SETTINGS_JSON="dots/hyprland/.config/settings/quickshell/config.json"

# Same as MERGE_DIR in upstream.sh: a conflicted manual update waiting to be resolved.
MERGE_DIR="${CLONE}-merge"
BAR_CONFIG="quickshell/ii/shell.qml"

STATE_FILE="$STATE_DIR/shell-update.json"
RUN_LOCK="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/dotfiles-shell-update.lock"

_started=""
_log=""
_step=""
# Rollback points, set right before the merge and cleared before the push.
_rb_clone=""
_rb_dotfiles=""
_rb_runtime=false

# ------------------------------------------------------------------
# Small readers
# ------------------------------------------------------------------
_pinned()          { awk -F"'" '/^_commit=/ {print $2; exit}' "$PKGBUILD" 2>/dev/null || true; }
_locked()          { awk -F= '$1=="commit" {print $2; exit}' "$LOCK_FILE" 2>/dev/null || true; }
_installed_pin()   { cat "$PIN_FILE" 2>/dev/null || true; }
_installed_date()  { LC_ALL=C pacman -Qi "$RUNTIME_PKG" 2>/dev/null | awk -F': ' '/^Install Date/ {print $2; exit}' || true; }

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

_phase() {
    _step="$1"
    step "$1"
    _state running "$1"
}

# A known failure: record why, tell the user, stop.
_fail_msg() {
    trap - ERR
    local msg="$1"
    error "$msg"
    _rollback && msg+=" Rolled back to the previous version." \
        || msg+=" ROLLBACK FAILED — see the log: $_log"
    _state error "$msg"
    run_notify "end-4 update failed" "$msg"
    exit 1
}

# Anything else that breaks under set -e lands here.
_fail_unexpected() {
    local rc=$?
    trap - ERR
    local msg="Failed during '$_step' (exit $rc)."
    error "$msg"
    _rollback && msg+=" Rolled back to the previous version." \
        || msg+=" ROLLBACK FAILED."
    msg+=" See the log: $_log"
    _state error "$msg"
    run_notify "end-4 update failed" "$msg"
    exit "$rc"
}

# ------------------------------------------------------------------
# Rollback — back to the last version that worked
# ------------------------------------------------------------------
# Returns 0 when there was nothing to undo or the undo worked. Uses --keep so
# files git does not own (per-machine, skip-worktree) are never clobbered.
_rollback() {
    [[ -n "$_rb_clone" ]] || return 0
    local ok=0
    set +e
    _step="Rollback"
    step "Rolling back"
    _state running "Rolling back"

    git -C "$CLONE" rev-parse -q --verify MERGE_HEAD >/dev/null && git -C "$CLONE" merge --abort
    if git -C "$CLONE" reset -q --keep "$_rb_clone"; then
        git -C "$CLONE" submodule update --init --recursive -q
        success "Clone back at ${_rb_clone:0:8}"
    else
        error "Could not reset the clone to $_rb_clone — try: git -C $CLONE reset --keep $_rb_clone"
        ok=1
    fi

    # Only the commits this run made, and they were never pushed (push comes last).
    if [[ "$(git -C "$DOTFILES_DIR" rev-parse HEAD)" != "$_rb_dotfiles" ]]; then
        if git -C "$DOTFILES_DIR" reset -q --keep "$_rb_dotfiles"; then
            success "Dropped this run's overlay commit"
        else
            error "Could not drop the overlay commit — try: git -C $DOTFILES_DIR reset --keep $_rb_dotfiles"
            ok=1
        fi
    fi

    # The clone is back on the old pin: reinstall that build (cached, no compile).
    if [[ "$_rb_runtime" == true ]]; then
        "$SETUP" upstream deps || { error "Could not reinstall the previous quickshell — run: setup upstream deps"; ok=1; }
    fi

    local errors
    errors="$(hypr_reload_errors)"
    [[ -z "$errors" ]] || { error "Hyprland still reports errors: $errors"; ok=1; }
    if [[ "$_bar_was_running" == true ]] && { [[ "$_rb_runtime" == true ]] || ! _bar_running; }; then
        run_restart_bar
    fi

    _rb_clone=""
    set -e
    return "$ok"
}

# ------------------------------------------------------------------
# Session health
# ------------------------------------------------------------------
_bar_was_running=false
_qs_log_mark=0

_bar_running() { qs list --all 2>/dev/null | grep -q "$BAR_CONFIG"; }
_bar_log()     { qs log -c ii 2>/dev/null || true; }

# The bar hot-reloads on file changes and keeps the old generation when the new
# QML fails, so it looks alive: the log is what says the new code is broken.
_check_session() {
    local errors
    errors="$(hypr_reload_errors)"
    [[ -z "$errors" ]] || _fail_msg "Hyprland reports config errors with the new end-4 code: ${errors%%$'\n'*}"

    [[ "$_bar_was_running" == true ]] || { success "Hyprland config loads cleanly"; return 0; }
    sleep 3
    _bar_running || _fail_msg "The bar stopped running with the new end-4 code."
    if _bar_log | tail -n +"$((_qs_log_mark + 1))" | grep -q "Failed to load configuration"; then
        _fail_msg "The bar failed to load the new end-4 code (see: qs log -c ii)."
    fi
    success "Hyprland config loads cleanly and the bar is up"
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
    if [[ -d "$MERGE_DIR" ]]; then
        _fail_msg "A manual end-4 merge is pending in $MERGE_DIR. Finish it with 'setup upstream update --finish' or drop it with '--abort'."
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

# upstream update left the conflicted merge in $MERGE_DIR, never in the live clone.
# Drop it: this run stays all-or-nothing, and a manual `upstream update` redoes it.
_abort_conflict() {
    local files=()
    mapfile -t files < <(git -C "$MERGE_DIR" diff --name-only --diff-filter=U 2>/dev/null)
    "$SETUP" upstream update --abort >/dev/null
    _rb_clone=""

    local msg="end-4 changed ${#files[@]} file(s) you also patch. Nothing was applied; your session is untouched."
    echo
    warn "$msg"
    printf '      %s\n' "${files[@]}"
    info "To merge by hand (in a separate copy, the session keeps working):"
    info "  $SETUP upstream update      fix the markers in $MERGE_DIR, git merge --continue there, then"
    info "  $SETUP upstream update --finish && $SETUP upstream export"
    _state conflict "$msg" "${files[@]}"
    run_notify "end-4 update: conflicts" "$msg"
    exit 2
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
    run_begin "$RUN_LOCK" shell-update
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
    # Baseline: a reload clears stale errors; real ones are not this update's doing.
    local errors
    errors="$(hypr_reload_errors)"
    [[ -z "$errors" ]] || _fail_msg "Hyprland already reports config errors before updating — fix them first: ${errors%%$'\n'*}"
    _bar_running && _bar_was_running=true
    _qs_log_mark="$(_bar_log | wc -l)"
    _rb_clone="$(git -C "$CLONE" rev-parse HEAD)"
    _rb_dotfiles="$(git -C "$DOTFILES_DIR" rev-parse HEAD)"
    local rc=0
    "$SETUP" upstream update || rc=$?
    case "$rc" in
        0) ;;
        2) _abort_conflict ;;
        *) _fail_msg "Merging end-4 failed, and not because of a conflict. See the log: $_log" ;;
    esac

    _phase "Check session"
    _check_session

    _phase "Export overlay"
    "$SETUP" upstream export
    local locked pinned
    locked="$(_locked)"
    pinned="$(_pinned)"
    _commit_paths "chore(upstream): actualizar end-4 a ${locked:0:7} (quickshell ${pinned:0:7})" overlay

    _phase "Runtime (quickshell)"
    local before after
    before="$(_installed_date)"
    _rb_runtime=true   # deps may have swapped the package before failing
    "$SETUP" upstream deps
    after="$(_installed_date)"
    [[ "$before" != "$after" ]] || _rb_runtime=false

    if [[ "$before" != "$after" ]]; then
        _phase "Restart bar"
        _qs_log_mark=0
        run_restart_bar
        _check_session
    fi

    # From here on the update is good; a failed push keeps it and says so.
    _rb_clone=""

    _phase "Push"
    _push

    _step="Done"
    local msg="end-4 at ${locked:0:7}, quickshell at ${pinned:0:7}."
    _state ok "$msg"
    step "Done"
    success "$msg"
    run_notify "end-4 update finished" "$msg"
}

cmd_status() {
    if [[ ! -d "$CLONE/.git" ]]; then
        jq -n --arg repo "$DOTFILES_DIR" --arg clone "$CLONE" \
            '{ok: false, error: "No upstream clone — run setup upstream sync", repo: $repo, clone: $clone}'
        return 0
    fi

    local fetched=true merging=false dirty=false abi=true running=false behind head upstream_pin
    run_is_alive "$RUN_LOCK" && running=true
    timeout 30 git -C "$CLONE" fetch -q origin 2>/dev/null || fetched=false
    behind="$(git -C "$CLONE" rev-list --count mine..origin/main 2>/dev/null || echo 0)"
    head="$(git -C "$CLONE" rev-parse --short=7 origin/main 2>/dev/null || true)"
    # The pin in end-4's latest code, which Update would bring in.
    upstream_pin="$(git -C "$CLONE" show "origin/main:$PKGBUILD_REL" 2>/dev/null \
        | awk -F"'" '/^_commit=/ {print $2; exit}' || true)"
    [[ -f "$CLONE/.git/MERGE_HEAD" || -d "$MERGE_DIR" ]] && merging=true
    [[ -n "$(git -C "$CLONE" status --porcelain 2>/dev/null)" ]] && dirty=true
    run_quickshell_loads || abi=false

    jq -n --arg repo "$DOTFILES_DIR" --arg clone "$CLONE" \
        --arg locked "$(_locked)" --arg upstreamHead "$head" --argjson behind "$behind" \
        --argjson fetched "$fetched" --argjson dirty "$dirty" --argjson merging "$merging" \
        --arg pinned "$(_pinned)" --arg upstreamPin "$upstream_pin" --arg installedPin "$(_installed_pin)" \
        --arg installedVersion "$(pacman -Q "$RUNTIME_PKG" 2>/dev/null | awk '{print $2}' || true)" \
        --argjson abiOk "$abi" --argjson running "$running" \
        '{ok: true, running: $running, repo: $repo, clone: $clone, locked: $locked, upstreamHead: $upstreamHead,
          behind: $behind, fetched: $fetched, dirty: $dirty, merging: $merging,
          pinned: $pinned, upstreamPin: $upstreamPin, installedPin: $installedPin, installedVersion: $installedVersion,
          abiOk: $abiOk,
          runtime: (if ($abiOk | not) then "abi"
                    elif $installedPin == "" then "untracked"
                    elif $pinned != $installedPin then "stale"
                    else "ok" end)}'
}

# Sourced (tests) = functions only.
[[ "${BASH_SOURCE[0]}" == "$0" ]] || return 0

case "${1:-}" in
    --status) cmd_status ;;
    "")       cmd_run ;;
    *)        error "Unknown option: $1"; exit 1 ;;
esac
