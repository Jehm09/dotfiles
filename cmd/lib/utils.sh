#!/usr/bin/env bash
# Shared utilities sourced by all setup scripts.
# Do not execute directly.

# ------------------------------------------------------------------
# Machine-local settings
# ------------------------------------------------------------------
# local.conf holds the handful of values that describe THIS machine rather than
# the configuration — which monitor the login screen is pinned to, and the like.
# It is gitignored on purpose: committing it would make the repo stop installing
# cleanly anywhere else, which is the whole reason those settings are not
# defaults in the first place.
#
# Sourced before anything reads its variables, and every one of them is written
# as ${VAR:-default}, so an environment variable passed on the command line
# still wins for a one-off run. See local.conf.example.
_UTILS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_LOCAL_CONF="${DOTFILES_LOCAL_CONF:-$(cd "$_UTILS_DIR/../.." && pwd)/local.conf}"
# shellcheck source=/dev/null
[[ -f "$DOTFILES_LOCAL_CONF" ]] && source "$DOTFILES_LOCAL_CONF"

# Persist a setting to local.conf, replacing any previous value for that key.
# Used when a run is given a value explicitly, so the next plain run keeps it.
local_conf_set() {
    local key="$1" value="$2"
    mkdir -p "$(dirname "$DOTFILES_LOCAL_CONF")"
    if [[ -f "$DOTFILES_LOCAL_CONF" ]]; then
        sed -i "/^${key}=/d" "$DOTFILES_LOCAL_CONF"
    else
        cat >"$DOTFILES_LOCAL_CONF" <<'EOF'
# Machine-local settings for this checkout. Gitignored.
# Written by setup; safe to edit by hand. See local.conf.example.
EOF
    fi
    echo "${key}=${value}" >>"$DOTFILES_LOCAL_CONF"
}

# ------------------------------------------------------------------
# Colors and print helpers
# ------------------------------------------------------------------
_CLR_RED='\033[0;31m'
_CLR_GREEN='\033[0;32m'
_CLR_YELLOW='\033[1;33m'
_CLR_CYAN='\033[0;36m'
_CLR_BOLD='\033[1m'
_CLR_RST='\033[0m'

info()    { echo -e "${_CLR_CYAN}==>${_CLR_RST} ${_CLR_BOLD}$*${_CLR_RST}"; }
success() { echo -e "${_CLR_GREEN}==>${_CLR_RST} $*"; }
warn()    { echo -e "${_CLR_YELLOW}==> WARNING:${_CLR_RST} $*"; }
error()   { echo -e "${_CLR_RED}==> ERROR:${_CLR_RST} $*" >&2; }
step()    { echo -e "\n${_CLR_BOLD}--- $* ---${_CLR_RST}"; }

# ------------------------------------------------------------------
# Interactive menus (whiptail)
# ------------------------------------------------------------------
# whiptail ships in libnewt, which is already pulled in as a dependency on any
# Arch system, and works on a bare TTY — which matters because 'setup post' is
# the first thing you run after the very first boot, before any desktop exists.
#
# Every helper degrades to a plain read-based prompt when whiptail is missing or
# stdin is not a terminal, so nothing here can wedge an automated run.
# ------------------------------------------------------------------
has_menu() { command -v whiptail &>/dev/null && [[ -t 0 ]]; }

# Dark theme. whiptail's default is the old Red Hat installer palette — a light
# grey window on a bright blue root — which is glaring next to a dark terminal.
#
# NEWT_COLORS takes "element=foreground,background" pairs, and newt only knows
# these sixteen names:
#
#   black  blue  green  cyan  red  magenta  brown  lightgray
#   gray   brightblue  brightgreen  brightcyan  brightred
#   brightmagenta  yellow  white
#
# Anything else — "brightwhite", "brightblack", an empty value — is not an error
# but is silently ignored, and the element keeps whatever the default palette
# had. That is how you end up with unreadable cyan-on-cyan text, so stick to the
# list above and always give both halves of the pair.
export NEWT_COLORS='
root=lightgray,black
window=lightgray,black
border=brightblue,black
shadow=black,black
title=brightcyan,black
textbox=lightgray,black
acttextbox=black,cyan
label=lightgray,black
entry=lightgray,black
disentry=gray,black
listbox=lightgray,black
actlistbox=black,cyan
sellistbox=brightcyan,black
actsellistbox=black,brightcyan
checkbox=lightgray,black
actcheckbox=black,cyan
button=black,cyan
actbutton=black,brightcyan
compactbutton=lightgray,black
helpline=gray,black
roottext=gray,black
emptyscale=black,gray
fullscale=black,brightcyan
'

# Checkbox list. Prints the chosen tags, one per line.
# Args: title, prompt, then triplets of  tag  label  on|off
menu_checklist() {
    local title="$1" prompt="$2"; shift 2
    local -a items=()
    while (($# >= 3)); do items+=("$1" "$2" "$3"); shift 3; done

    local rows=$(( ${#items[@]} / 3 ))
    # --separate-output gives one tag per line instead of a quoted single line.
    whiptail --title "$title" --separate-output \
        --checklist "$prompt" $((rows + 9)) 74 "$rows" \
        "${items[@]}" 3>&1 1>&2 2>&3
}

# Single choice. Prints the chosen tag.
# Args: title, prompt, then triplets of  tag  label  on|off
menu_radiolist() {
    local title="$1" prompt="$2"; shift 2
    local -a items=()
    while (($# >= 3)); do items+=("$1" "$2" "$3"); shift 3; done

    local rows=$(( ${#items[@]} / 3 ))
    whiptail --title "$title" \
        --radiolist "$prompt" $((rows + 9)) 74 "$rows" \
        "${items[@]}" 3>&1 1>&2 2>&3
}

menu_confirm() {
    local title="$1" prompt="$2"
    whiptail --title "$title" --yesno "$prompt" 12 74
}

# ------------------------------------------------------------------
# Package list parser
# Strips comments and blank lines, returns one package name per line.
# ------------------------------------------------------------------
parse_packages() {
    grep -v '^\s*#' "$1" \
        | grep -v '^\s*##' \
        | grep -v '^\s*$' \
        | awk '{print $1}' \
        | grep -v '^$'
}

# ------------------------------------------------------------------
# Multilib repository
# Enables the [multilib] section in /etc/pacman.conf (required for Steam).
# ------------------------------------------------------------------
multilib_enable() {
    if grep -q '^\[multilib\]' /etc/pacman.conf; then
        info "multilib already enabled"
        return 0
    fi
    info "Enabling multilib repository..."
    sudo sed -i '/^#\[multilib\]/{
        s/^#//
        n
        s/^#Include/Include/
    }' /etc/pacman.conf
    sudo pacman -Sy --noconfirm
    success "multilib enabled"
}

# ------------------------------------------------------------------
# Sudo keepalive
# Refreshes the sudo timestamp in the background so long installs
# do not time out and prompt for a password mid-run.
# Call sudo_keepalive at the start; the EXIT trap calls sudo_stop_keepalive.
# ------------------------------------------------------------------
sudo_keepalive() {
    sudo -v
    (
        while true; do
            sleep 55
            sudo -v
        done
    ) &
    _SUDO_KEEPALIVE_PID=$!
}

sudo_stop_keepalive() {
    if [[ -n "${_SUDO_KEEPALIVE_PID:-}" ]]; then
        kill "$_SUDO_KEEPALIVE_PID" 2>/dev/null || true
        unset _SUDO_KEEPALIVE_PID
    fi
}

# ------------------------------------------------------------------
# Safety check: refuse to run as root where not expected.
# ------------------------------------------------------------------
prevent_root() {
    if [[ "$EUID" -eq 0 ]]; then
        error "Do not run this as root. Use your regular user account."
        error "sudo will be called automatically when needed."
        exit 1
    fi
}
