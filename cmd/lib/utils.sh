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
    # Single-quoted: values carry spaces and ';' (a monitor description, say),
    # and this file is sourced. Embedded quotes are escaped the shell way.
    printf "%s='%s'\n" "$key" "${value//\'/\'\\\'\'}" >>"$DOTFILES_LOCAL_CONF"
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

# Focus starts on the list, not on the buttons — Ok/Cancel are the very bottom
# row, reached only with Tab, and there is nothing on screen that says so.
# Esc happens to work too, but is not spelled out here on purpose: some
# terminals/multiplexers hold it back waiting to see if more bytes follow (it
# is also the first byte of every arrow key), so it can take a long timeout to
# register, or never reach whiptail at all. Tab, then Enter, always works.
_MENU_NAV_HINT="(Tab to reach Ok/Cancel, Enter selects)"
_MENU_WIDTH=74
# Inner text width whiptail actually wraps to, once its border and padding are
# subtracted. Matched to _MENU_WIDTH, not guessed: get this wrong in either
# direction and the line count below stops matching what whiptail draws.
_MENU_TEXT_WIDTH=$(( _MENU_WIDTH - 4 ))

# Rendered height needed for a whiptail message: real newlines and whiptail's
# own literal "\n" both count, AND each resulting line that is still too long
# gets word-wrapped into more lines by whiptail itself — so this counts lines
# the same way whiptail will, with the same wrap width, instead of a flat
# constant that was only ever right for a one-line prompt.
#
# `awk 'END{print NR}'`, not `wc -l`: the prompt often ends without a trailing
# newline (this file's hint is the last thing appended), and wc -l does not
# count that final, unterminated line.
_menu_text_lines() {
    printf '%s' "$1" | sed 's/\\n/\n/g' | fold -s -w "$_MENU_TEXT_WIDTH" | awk 'END{print NR}'
}

# Checkbox list. Prints the chosen tags, one per line.
# Args: title, prompt, then triplets of  tag  label  on|off
menu_checklist() {
    local title="$1" prompt="$2"; shift 2
    local -a items=()
    while (($# >= 3)); do items+=("$1" "$2" "$3"); shift 3; done

    local rows=$(( ${#items[@]} / 3 ))
    local full_prompt="$prompt"$'\n'"$_MENU_NAV_HINT — Space toggles"
    local text_lines; text_lines=$(_menu_text_lines "$full_prompt")
    # +6: 2 border rows, a blank line above the list and one above the button
    # row, the button row itself, and one line of breathing room — the exact
    # chrome whiptail adds around the text and the list, checked against its
    # actual output rather than assumed.
    whiptail --title "$title" --separate-output \
        --checklist "$full_prompt" $((text_lines + rows + 6)) "$_MENU_WIDTH" "$rows" \
        "${items[@]}" 3>&1 1>&2 2>&3
}

# Single choice. Prints the chosen tag.
# Args: title, prompt, then triplets of  tag  label  on|off
menu_radiolist() {
    local title="$1" prompt="$2"; shift 2
    local -a items=()
    while (($# >= 3)); do items+=("$1" "$2" "$3"); shift 3; done

    local rows=$(( ${#items[@]} / 3 ))
    local full_prompt="$prompt"$'\n'"$_MENU_NAV_HINT"
    local text_lines; text_lines=$(_menu_text_lines "$full_prompt")
    whiptail --title "$title" \
        --radiolist "$full_prompt" $((text_lines + rows + 6)) "$_MENU_WIDTH" "$rows" \
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
