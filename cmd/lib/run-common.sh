#!/usr/bin/env bash
#
# run-common.sh — shared by the update runs the quickshell Update page launches
# (shell-update.sh, system-update.sh). Sourced, never run. Expects utils.sh.
#
#   run_begin <lock> <name>   one run at a time + full output to a log
#   run_notify <title> <body> desktop notification, never fails
#   run_restart_bar           restart the bar on a freshly installed quickshell
#   run_quickshell_loads      false when a Qt upgrade broke the installed quickshell

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles"

# Sets _started and _log. fd 9 holds the lock for the life of the process.
run_begin() {   # run_begin <lock file> <log name>
    mkdir -p "$STATE_DIR/logs"
    exec 9>"$1"
    flock -n 9 || { error "Another '$2' run is already in progress."; exit 1; }

    _started="$(date -Iseconds)"
    _log="$STATE_DIR/logs/$2-$(date +%Y%m%d-%H%M%S).log"
    # In a terminal: screen + log. Launched from the shell (no terminal): log only.
    if [[ -t 1 ]]; then
        exec > >(tee -a "$_log") 2>&1
    else
        exec >>"$_log" 2>&1 </dev/null
    fi
}

# True while a run holds the lock (the state file alone says "running" forever
# if the terminal was closed mid-run).
run_is_alive() {   # run_is_alive <lock file>
    [[ -e "$1" ]] && ! flock -n "$1" true
}

run_notify() {
    command -v notify-send &>/dev/null || return 0
    notify-send -a "Dotfiles" "$1" "$2" 2>/dev/null || true
}

# Only the bar (config ii); the settings window is another instance (-p settings.qml).
# The crash-handler variables are dropped for the same reason as QsLaunch.qml,
# and fd 9 (the run lock) is closed so the new bar does not keep holding it.
run_restart_bar() {
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

# quickshell links Qt's private API: a qt6-base upgrade breaks it without
# changing its version, and it only shows up when the bar next starts.
run_quickshell_loads() {
    command -v quickshell &>/dev/null || return 0
    quickshell --private-check-compat &>/dev/null
}
