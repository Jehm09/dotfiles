#!/usr/bin/env bash
# Shared utilities sourced by all setup scripts.
# Do not execute directly.

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
