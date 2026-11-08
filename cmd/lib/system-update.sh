#!/usr/bin/env bash
#
# system-update.sh — official repos + AUR as one logged run, for the "Update"
# page in quickshell settings and the "update before shutdown" prompt of the
# session screen (both run it with --background and show a loader; nothing opens).
#
#   setup update system                          paru/yay -Syu, interactive
#   setup update system --unattended             no prompts: anything that needs
#                                                an answer fails instead of waiting
#   setup update system --unattended --then poweroff|reboot|windows
#                                                same, then power off / reboot /
#                                                reboot into Windows (one boot only) —
#                                                only if it succeeded
#   setup update system --status                 JSON snapshot, changes nothing
#   setup update system --background ...         --unattended without a terminal: what
#                                                the quickshell loader launches. Output
#                                                only in the log; sudo answers through
#                                                SUDO_ASKPASS; the power off countdown is
#                                                cancelled from the loader ($POWER_CANCEL_FILE)
#   ... --sudo-pass-file <file>                  password typed in the quickshell box;
#                                                deleted when the run ends (in a terminal,
#                                                falls back to asking there)
#
# Two passes: the official repos first (a failure there stops everything, the
# power off/reboot included) and then the AUR, where a package that does not
# build only warns — the old version stays installed and the run goes on.
# After the upgrade the pinned quickshell is rebuilt if the new Qt broke it,
# otherwise the bar would not come back after the reboot.
#
# Progress goes to $STATE_FILE (read by the settings page) and the full output
# to a log under $STATE_DIR/logs.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$DOTFILES_DIR/cmd/lib/utils.sh"
source "$DOTFILES_DIR/cmd/lib/run-common.sh"

SETUP="$DOTFILES_DIR/setup"
STATE_FILE="$STATE_DIR/system-update.json"
RUN_LOCK="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/dotfiles-system-update.lock"
PACMAN_DB_LOCK="/var/lib/pacman/db.lck"
# Own sync db for checkupdates, so it never races end-4's Updates.qml on the default one.
export CHECKUPDATES_DB="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/checkup-db"
# Seconds to cancel the power off / reboot after a successful run.
POWER_COUNTDOWN=10
# The loader's Cancel button creates it, during the run or the countdown.
POWER_CANCEL_FILE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/dotfiles-system-update.cancel-power"

_unattended=false
_background=false
_askpass_dir=""
# Epoch when the power off happens; 0 = no countdown. The loader shows it.
_power_at=0
_then=""
_pass_file=""
_aur_failed=()
_started=""
_log=""
_step=""

# ------------------------------------------------------------------
# Readers
# ------------------------------------------------------------------
_helper() {
    local h
    for h in paru yay; do
        command -v "$h" &>/dev/null && { echo "$h"; return 0; }
    done
    return 0
}

# Every "name old -> new" line as {name, from, to}; warnings and the packages in
# IgnorePkg (pacman/paru print them with a trailing "[ignored]") are dropped.
_updates_json() {
    awk '$3 == "->" && $NF != "[ignored]" {print $1 "\t" $2 "\t" $4}' \
        | jq -R -s -c 'split("\n") | map(select(length > 0) | split("\t")
                       | {name: .[0], from: .[1], to: .[2]})'
}

# Titles of the Arch news newer than the installed packages ("YYYY-MM-DD Title").
_news_titles() {
    sed 's/\x1b\[[0-9;]*m//g' | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2} ' || true
}

# find exits 1 on the /etc dirs a user cannot read, but still lists the rest.
_pacnew_files() {
    { find /etc \( -name '*.pacnew' -o -name '*.pacsave' \) 2>/dev/null || true; } | sort
}

# Why a reboot is needed, one reason per line (empty = not needed).
_reboot_reasons() {
    local running pkgbase installed
    running="$(uname -r)"
    if [[ ! -d "/usr/lib/modules/$running" ]]; then
        pkgbase="$(sed -n 's|.*BOOT_IMAGE=[^ ]*/vmlinuz-\([^ ]*\).*|\1|p' /proc/cmdline)"
        installed="$(pacman -Q "${pkgbase:-linux}" 2>/dev/null | awk '{print $2}' || true)"
        echo "Kernel: running $running, installed ${installed:-a newer one}"
    fi

    # The loaded NVIDIA module against the installed driver package.
    if [[ -r /sys/module/nvidia/version ]]; then
        local loaded pkg version
        loaded="$(cat /sys/module/nvidia/version)"
        pkg="$(pacman -Qq nvidia-open-dkms nvidia-open nvidia-dkms nvidia nvidia-lts nvidia-open-lts 2>/dev/null | head -1 || true)"
        if [[ -n "$pkg" ]]; then
            version="$(pacman -Q "$pkg" | awk '{print $2}')"
            version="${version#*:}"
            version="${version%-*}"
            [[ "$version" != "$loaded" ]] && echo "NVIDIA driver: loaded $loaded, installed $version"
        fi
    fi
    return 0
}

# Packages pacman upgraded/installed since $1 (ISO date), from its own log.
_changed_since() {
    local since="${1:0:19}"
    awk -v since="$since" '
        substr($0, 2, 19) >= since && / \[ALPM\] (upgraded|installed) / {n++}
        END {print n + 0}' /var/log/pacman.log 2>/dev/null || echo 0
}

# ------------------------------------------------------------------
# State file
# ------------------------------------------------------------------
_state() {   # _state <state> <message>
    local state="$1" message="$2" finished="" changed=0 reboot pacnew
    [[ "$state" != running ]] && finished="$(date -Iseconds)"
    [[ -n "$_started" ]] && changed="$(_changed_since "$_started")"
    reboot="$(_reboot_reasons | jq -R -s -c 'split("\n") | map(select(length > 0))')"
    pacnew="$(_pacnew_files | jq -R -s -c 'split("\n") | map(select(length > 0))')"
    mkdir -p "$STATE_DIR"
    jq -n --arg state "$state" --arg step "$_step" --arg message "$message" \
        --arg started "$_started" --arg finished "$finished" --arg log "$_log" \
        --arg then "$_then" --argjson unattended "$_unattended" --argjson changed "$changed" \
        --argjson powerAt "$_power_at" \
        --argjson reboot "$reboot" --argjson pacnew "$pacnew" \
        --argjson aurFailed "$(printf '%s\n' "${_aur_failed[@]}" | jq -R -s -c 'split("\n") | map(select(length > 0))')" \
        '{state: $state, step: $step, message: $message, started: $started, finished: $finished,
          log: $log, then: $then, unattended: $unattended, changed: $changed, powerAt: $powerAt,
          rebootReasons: $reboot, pacnew: $pacnew, aurFailed: $aurFailed}' >"$STATE_FILE.tmp"
    mv "$STATE_FILE.tmp" "$STATE_FILE"
}

_phase() {
    _step="$1"
    step "$1"
    _state running "$1"
}

_not_powering_off() {
    [[ -n "$_then" ]] && echo " Not doing the $_then — check the log first."
    return 0
}

_fail_msg() {
    trap - ERR
    local msg="$1$(_not_powering_off)"
    error "$msg"
    _state error "$msg"
    run_notify "System update failed" "$msg"
    exit 1
}

_fail_unexpected() {
    local rc=$?
    # set -E hands the trap to $(...) subshells too: only the main process reports.
    [[ "$BASHPID" == "$$" ]] || exit "$rc"
    trap - ERR
    local msg="Failed during '$_step' (exit $rc).$(_not_powering_off) Log: $_log"
    error "$msg"
    _state error "$msg"
    run_notify "System update failed" "$msg"
    exit "$rc"
}

# ------------------------------------------------------------------
# Steps
# ------------------------------------------------------------------
_upgrade_command() {   # _upgrade_command repo|aur — one word per line, nothing if it does not apply
    local h
    h="$(_helper)"
    case "$h:$1" in
        paru:repo) printf '%s\n' paru -Syu --repo ;;
        paru:aur)  printf '%s\n' paru -Sua ;;
        yay:repo)  printf '%s\n' yay -Syu --repo ;;
        yay:aur)   printf '%s\n' yay -Sua ;;
        :repo)     printf '%s\n' sudo pacman -Syu ;;
        *)         return 0 ;;
    esac
    $_unattended || return 0
    case "$h" in
        paru) printf '%s\n' --noconfirm --skipreview ;;
        yay)  printf '%s\n' --noconfirm --answerclean None --answerdiff None --answeredit None --answerupgrade None ;;
        *)    printf '%s\n' --noconfirm ;;
    esac
    return 0
}

# The password from the quickshell box: written to $XDG_RUNTIME_DIR (tmpfs, 0600),
# deleted before use, and fed to sudo through a builtin so it never shows in ps.
# sudo caches it for this terminal, so sudo_keepalive then finds it fresh.
_unlock_sudo_from_file() {
    [[ -n "$_pass_file" ]] || return 0
    local pw=""
    if [[ -f "$_pass_file" ]]; then
        pw="$(<"$_pass_file")"
        rm -f "$_pass_file"
    fi
    if [[ -n "$pw" ]] && printf '%s\n' "$pw" | sudo -S -p '' -v 2>/dev/null; then
        success "sudo unlocked with the password from the box"
    else
        warn "The password from the box did not work — sudo will ask here."
    fi
    pw=""
    return 0
}

# Without a terminal sudo caches nothing between processes (no tty to key the
# timestamp on), and paru/makepkg/deps each call it. A `sudo` first in PATH adds
# -A, and the askpass prints the password from a 0600 file in $XDG_RUNTIME_DIR
# that lives exactly as long as the run (the EXIT trap deletes it).
_unlock_sudo_askpass() {
    [[ -n "$_pass_file" && -s "$_pass_file" ]] \
        || _fail_msg "No password from the box — the background update needs one."
    _askpass_dir="$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/dotfiles-sudo-run.XXXXXX")"
    # Moved, not copied: the box's 60 s cleanup timer then has nothing to delete.
    mv -- "$_pass_file" "$_askpass_dir/pass"
    _pass_file="$_askpass_dir/pass"
    chmod 600 "$_pass_file"
    printf '#!/bin/sh\ncat %q\n' "$_pass_file" >"$_askpass_dir/askpass"
    printf '#!/bin/sh\nexec /usr/bin/sudo -A "$@"\n' >"$_askpass_dir/sudo"
    chmod 700 "$_askpass_dir/askpass" "$_askpass_dir/sudo"
    export SUDO_ASKPASS="$_askpass_dir/askpass"
    export PATH="$_askpass_dir:$PATH"
    sudo -v || _fail_msg "sudo did not accept the password from the box."
    success "sudo unlocked with the password from the box"
}

# Number of the "Windows Boot Manager" UEFI entry (e.g. 0002); empty without dual boot.
_windows_boot_entry() {
    efibootmgr 2>/dev/null | sed -n 's/^Boot\([0-9A-Fa-f]\{4\}\)\*\{0,1\} Windows Boot Manager.*/\1/p' | head -1
}

_power() {   # _power <final state> <final message>
    local label="${_then^}"
    [[ "$_then" == windows ]] && label="Reboot into Windows"
    _power_at=$(($(date +%s) + POWER_COUNTDOWN))
    _state "$1" "$2"
    echo
    if [[ -t 0 ]]; then
        info "$label in ${POWER_COUNTDOWN}s — press any key to cancel"
    else
        info "$label in ${POWER_COUNTDOWN}s — Cancel in the shell stops it"
    fi
    local key=""
    while (($(date +%s) < _power_at)); do
        if [[ -e "$POWER_CANCEL_FILE" ]] || { [[ -t 0 ]] && read -r -t 0.5 -n 1 -s key; }; then
            rm -f -- "$POWER_CANCEL_FILE"
            _power_at=0
            _state "$1" "$2 $label cancelled."
            warn "$label cancelled."
            return 0
        fi
        [[ -t 0 ]] || sleep 0.5
    done
    info "$label…"
    case "$_then" in
        poweroff) systemctl poweroff || loginctl poweroff ;;
        reboot)   systemctl reboot   || loginctl reboot   ;;
        windows)
            # BootNext vale para un solo arranque: el siguiente vuelve a GRUB.
            local entry
            entry="$(_windows_boot_entry)"
            if [[ -z "$entry" ]] || ! sudo efibootmgr --bootnext "$entry" >/dev/null; then
                warn "Could not set Windows as the next boot — not rebooting."
                return 0
            fi
            systemctl reboot || loginctl reboot
            ;;
    esac
}

# ------------------------------------------------------------------
# Commands
# ------------------------------------------------------------------
cmd_run() {
    run_begin "$RUN_LOCK" system-update
    trap _fail_unexpected ERR
    # The password file never outlives the run, even if it stops before reading it.
    trap 'sudo_stop_keepalive; rm -f -- "${_pass_file:-/nonexistent}"; [[ -z "$_askpass_dir" ]] || rm -rf -- "$_askpass_dir"' EXIT

    _phase "Preflight"
    rm -f -- "$POWER_CANCEL_FILE"   # left over from an earlier run
    [[ -e "$PACMAN_DB_LOCK" ]] \
        && _fail_msg "pacman is already running (or crashed and left $PACMAN_DB_LOCK)."
    local helper
    helper="$(_helper)"
    [[ -z "$helper" ]] && warn "No AUR helper found — updating the official repos only."
    $_unattended && info "Unattended: anything that needs an answer fails instead of waiting."
    if $_background; then
        _unlock_sudo_askpass
    else
        _unlock_sudo_from_file
    fi
    # One password up front (no prompt if the box already unlocked sudo); the
    # keepalive covers long AUR or quickshell builds.
    sudo_keepalive

    if [[ -n "$helper" ]]; then
        _phase "Arch news"
        local news
        news="$("$helper" -Pw 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' || true)"
        if [[ -n "$(_news_titles <<<"$news")" ]]; then
            warn "Arch news newer than your packages — read it if the update breaks something:"
            echo "$news" | sed 's/^/      /'
        else
            success "No unread Arch news"
        fi
    fi

    _phase "Upgrade repo packages"
    local cmd=() rc=0
    mapfile -t cmd < <(_upgrade_command repo)
    info "${cmd[*]}"
    "${cmd[@]}" || rc=$?
    ((rc == 0)) || _fail_msg "Upgrading the official repos failed (${cmd[0]}, exit $rc)."

    mapfile -t cmd < <(_upgrade_command aur)
    if ((${#cmd[@]})); then
        _phase "Upgrade AUR packages"
        info "${cmd[*]}"
        # Where this pass starts in the log, to pick out what failed to build.
        local log_from
        log_from=$(($(wc -l <"$_log") + 1))
        rc=0
        "${cmd[@]}" || rc=$?
        if ((rc != 0)); then
            sleep 1   # tee writes the log asynchronously: let it catch up
            mapfile -t _aur_failed < <(tail -n "+$log_from" "$_log" | sed 's/\x1b\[[0-9;]*m//g' \
                | sed -n 's/.*packages failed to build: //p' | tr ' ' '\n' \
                | sed -E 's/-[^-]+-[^-]+$//' | grep -v '^$' | sort -u || true)
            ((${#_aur_failed[@]})) || _aur_failed=("unknown (exit $rc)")
            warn "AUR packages that did not build (the installed version stays): ${_aur_failed[*]}"
        fi
    fi

    _phase "Check quickshell"
    if run_quickshell_loads; then
        success "quickshell still loads with the installed Qt"
    else
        warn "The new Qt broke the installed quickshell — rebuilding it"
        "$SETUP" upstream deps
        # Rebooting starts it anyway.
        [[ -z "$_then" ]] && run_restart_bar
    fi

    _step="Done"
    local changed reasons pacnew msg
    changed="$(_changed_since "$_started")"
    reasons="$(_reboot_reasons)"
    pacnew="$(_pacnew_files | wc -l)"
    msg="$changed package(s) upgraded or installed."
    ((${#_aur_failed[@]})) && msg+=" AUR did not build: ${_aur_failed[*]} (kept the installed version)."
    ((pacnew)) && msg+=" $pacnew .pacnew/.pacsave file(s) to merge."
    [[ -n "$reasons" && -z "$_then" ]] && msg+=" Reboot needed."
    local final=ok title="System update finished"
    if ((${#_aur_failed[@]})); then
        final=warning
        title="System update finished with AUR failures"
    fi
    _state "$final" "$msg"
    step "Done"
    if [[ "$final" == ok ]]; then success "$msg"; else warn "$msg"; fi
    [[ -n "$reasons" ]] && sed 's/^/      /' <<<"$reasons"
    run_notify "$title" "$msg"

    [[ -n "$_then" ]] && _power "$final" "$msg"
    return 0
}

cmd_status() {
    local helper running=false
    helper="$(_helper)"
    # Global: the EXIT trap runs after this function's locals are gone.
    _status_tmp="$(mktemp -d)"
    trap 'rm -rf "$_status_tmp"' EXIT
    local tmp="$_status_tmp"
    run_is_alive "$RUN_LOCK" && running=true
    : >"$tmp/news"

    # The three network checks run side by side: ~1-3 s each. `&& … ||` keeps set -e from
    # killing the subshell on the expected non-zero exits (checkupdates 2, -Qua 1 = nothing new).
    if command -v checkupdates &>/dev/null; then
        mkdir -p "$CHECKUPDATES_DB"
        { timeout 60 checkupdates >"$tmp/repo" 2>"$tmp/repo.err" && echo 0 || echo $?; } >"$tmp/repo.rc" &
    fi
    if [[ -n "$helper" ]]; then
        { timeout 60 "$helper" -Qua >"$tmp/aur" 2>"$tmp/aur.err" && echo 0 || echo $?; } >"$tmp/aur.rc" &
        { timeout 30 "$helper" -Pw >"$tmp/news" 2>/dev/null || true; } &
    fi
    wait

    local repo_json='{"checked": false, "error": "checkupdates is missing — install pacman-contrib", "packages": []}'
    if [[ -f "$tmp/repo.rc" ]]; then
        # checkupdates: 0 = updates, 2 = none, anything else = it could not check.
        local rc
        rc="$(cat "$tmp/repo.rc")"
        if [[ "$rc" == 0 || "$rc" == 2 ]]; then
            repo_json="$(jq -n --argjson p "$(_updates_json <"$tmp/repo")" '{checked: true, error: "", packages: $p}')"
        else
            repo_json="$(jq -n --arg e "$(tail -1 "$tmp/repo.err" 2>/dev/null)" \
                '{checked: false, error: ("Could not check the repos (offline?) " + $e), packages: []}')"
        fi
    fi

    local aur_json='{"checked": false, "error": "No AUR helper (paru or yay) installed", "packages": []}'
    if [[ -n "$helper" ]]; then
        # -Qua exits 1 when there is nothing to upgrade; only a timeout means it failed.
        if [[ "$(cat "$tmp/aur.rc")" == 124 ]]; then
            aur_json='{"checked": false, "error": "The AUR did not answer (offline?)", "packages": []}'
        else
            aur_json="$(jq -n --argjson p "$(_updates_json <"$tmp/aur")" '{checked: true, error: "", packages: $p}')"
        fi
    fi

    jq -n --arg helper "$helper" --argjson running "$running" \
        --argjson repo "$repo_json" --argjson aur "$aur_json" \
        --argjson news "$(_news_titles <"$tmp/news" | jq -R -s -c 'split("\n") | map(select(length > 0))')" \
        --argjson reboot "$(_reboot_reasons | jq -R -s -c 'split("\n") | map(select(length > 0))')" \
        --argjson pacnew "$(_pacnew_files | jq -R -s -c 'split("\n") | map(select(length > 0))')" \
        --argjson ignored "$(pacman-conf IgnorePkg 2>/dev/null | jq -R -s -c 'split("\n") | map(select(length > 0))')" \
        --argjson pmRunning "$([[ -e "$PACMAN_DB_LOCK" ]] && echo true || echo false)" \
        --arg checkedAt "$(date -Iseconds)" \
        '{ok: true, helper: $helper, running: $running, packageManagerRunning: $pmRunning,
          checkedAt: $checkedAt, repo: $repo, aur: $aur,
          count: (($repo.packages | length) + ($aur.packages | length)),
          news: $news, rebootReasons: $reboot, pacnew: $pacnew, ignored: $ignored}'
}

# Sourced (tests) = functions only.
[[ "${BASH_SOURCE[0]}" == "$0" ]] || return 0

# ------------------------------------------------------------------
# Flags
# ------------------------------------------------------------------
_mode=run
while [[ $# -gt 0 ]]; do
    case "$1" in
        --status)     _mode=status ;;
        --unattended) _unattended=true ;;
        --background) _background=true; _unattended=true ;;
        --sudo-pass-file)
            _pass_file="${2:-}"
            shift
            ;;
        --then)
            [[ "${2:-}" =~ ^(poweroff|reboot|windows)$ ]] \
                || { error "--then takes 'poweroff', 'reboot' or 'windows'."; exit 1; }
            _then="$2"
            shift
            ;;
        *) error "Unknown option: $1"; exit 1 ;;
    esac
    shift
done

case "$_mode" in
    status) cmd_status ;;
    run)    cmd_run ;;
esac
