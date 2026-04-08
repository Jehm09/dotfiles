#!/usr/bin/env bash
# Post-install setup — run after first boot into the new Arch system.
# Handles everything archinstall cannot: multilib, AUR helper, AUR packages,
# pacman hooks, dotfiles symlinks, and default shell.
#
# Usage:
#   setup post              Interactive component selection (default)
#   setup post --all        Run everything without prompting
#   setup post --dotfiles   Only link dotfiles
#   setup post --aur        Only install AUR helper + AUR packages

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$REPO_ROOT/lib/utils.sh"

prevent_root
sudo_keepalive
trap sudo_stop_keepalive EXIT INT TERM

# ------------------------------------------------------------------
# Defaults
# ------------------------------------------------------------------
_do_multilib=true
_do_aur_helper=true
_aur_helper="paru"        # paru | yay
_do_aur_pkgs=true
_do_hooks=true
_do_dotfiles=true
_do_shell=true

_flag_noninteractive=false

# ------------------------------------------------------------------
# Parse flags
# ------------------------------------------------------------------
for arg in "$@"; do
    case "$arg" in
        --all)
            _flag_noninteractive=true
            ;;
        --dotfiles)
            _do_multilib=false; _do_aur_helper=false
            _do_aur_pkgs=false; _do_hooks=false; _do_shell=false
            _flag_noninteractive=true
            ;;
        --aur)
            _do_multilib=false; _do_hooks=false
            _do_dotfiles=false; _do_shell=false
            _flag_noninteractive=true
            ;;
        -h|--help)
            cat <<EOF
Usage: setup post [options]

Options:
    --all          Run all components without prompting
    --dotfiles     Only link dotfiles (~/.config symlinks)
    --aur          Only install AUR helper + AUR packages
    -h, --help     Show this help

Interactive mode (default, no flags):
    A menu lets you toggle each component before confirming.
EOF
            exit 0
            ;;
    esac
done

# ------------------------------------------------------------------
# Interactive menu
# ------------------------------------------------------------------
_print_menu() {
    echo ""
    echo -e "${_CLR_BOLD}Select post-install components:${_CLR_RST}"
    echo ""
    printf "  [%s] 1  Multilib repository  (required for Steam and 32-bit apps)\n" \
        "$([[ $_do_multilib    == true ]] && echo "x" || echo " ")"
    printf "  [%s] 2  AUR helper           (currently: %s)\n" \
        "$([[ $_do_aur_helper  == true ]] && echo "x" || echo " ")" "$_aur_helper"
    printf "  [%s] 3  AUR packages         (from packages/aur.conf)\n" \
        "$([[ $_do_aur_pkgs    == true ]] && echo "x" || echo " ")"
    printf "  [%s] 4  Pacman hooks         (from packages/hooks/)\n" \
        "$([[ $_do_hooks       == true ]] && echo "x" || echo " ")"
    printf "  [%s] 5  Dotfiles             (~/.config symlinks)\n" \
        "$([[ $_do_dotfiles    == true ]] && echo "x" || echo " ")"
    printf "  [%s] 6  Fish as default shell\n" \
        "$([[ $_do_shell       == true ]] && echo "x" || echo " ")"
    echo ""
    echo "  Toggle: enter numbers (e.g. 3 5)"
    echo "  Change AUR helper: enter 'p' for paru, 'y' for yay"
    echo "  Press Enter to confirm and run"
}

if [[ "$_flag_noninteractive" == false && -t 0 ]]; then
    _print_menu
    while true; do
        read -rp "> " _sel
        [[ -z "$_sel" ]] && break
        for token in $_sel; do
            case "$token" in
                1) [[ $_do_multilib   == true ]] && _do_multilib=false   || _do_multilib=true   ;;
                2) [[ $_do_aur_helper == true ]] && _do_aur_helper=false || _do_aur_helper=true ;;
                3) [[ $_do_aur_pkgs   == true ]] && _do_aur_pkgs=false   || _do_aur_pkgs=true   ;;
                4) [[ $_do_hooks      == true ]] && _do_hooks=false      || _do_hooks=true      ;;
                5) [[ $_do_dotfiles   == true ]] && _do_dotfiles=false   || _do_dotfiles=true   ;;
                6) [[ $_do_shell      == true ]] && _do_shell=false      || _do_shell=true      ;;
                p) _aur_helper="paru" ;;
                y) _aur_helper="yay"  ;;
            esac
        done
        _print_menu
    done
    echo ""
fi

# ------------------------------------------------------------------
# 1. Multilib
# ------------------------------------------------------------------
if [[ $_do_multilib == true ]]; then
    step "Multilib repository"
    multilib_enable
fi

# ------------------------------------------------------------------
# 2. AUR helper (paru or yay)
# ------------------------------------------------------------------
if [[ $_do_aur_helper == true ]]; then
    step "AUR helper ($_aur_helper)"

    if command -v "$_aur_helper" &>/dev/null; then
        info "$_aur_helper is already installed, skipping"
    else
        AUR_TMP=$(mktemp -d)
        trap 'rm -rf "$AUR_TMP"; sudo_stop_keepalive' EXIT INT TERM
        git clone "https://aur.archlinux.org/${_aur_helper}.git" "$AUR_TMP"
        (cd "$AUR_TMP" && makepkg -si --noconfirm)
        success "$_aur_helper installed"
    fi
fi

# ------------------------------------------------------------------
# 3. AUR packages
# ------------------------------------------------------------------
if [[ $_do_aur_pkgs == true ]]; then
    step "AUR packages"

    # Use whichever helper is available (prefer paru, fallback yay)
    _helper=""
    for h in paru yay; do
        command -v "$h" &>/dev/null && { _helper="$h"; break; }
    done

    if [[ -z "$_helper" ]]; then
        warn "No AUR helper found — skipping AUR packages (enable step 2 to install one)"
    else
        mapfile -t _pkgs < <(parse_packages "$REPO_ROOT/packages/aur.conf")
        if [[ ${#_pkgs[@]} -gt 0 ]]; then
            info "Installing ${#_pkgs[@]} AUR packages with $_helper..."
            "$_helper" -S --needed --noconfirm "${_pkgs[@]}"
            success "AUR packages installed"
        else
            warn "No packages found in aur.conf"
        fi
    fi
fi

# ------------------------------------------------------------------
# 4. Pacman hooks
# ------------------------------------------------------------------
if [[ $_do_hooks == true ]]; then
    step "Pacman hooks"
    HOOKS_SRC="$REPO_ROOT/packages/hooks"
    if [[ -d "$HOOKS_SRC" ]] && compgen -G "$HOOKS_SRC/*.hook" > /dev/null; then
        sudo mkdir -p /etc/pacman.d/hooks
        for hook in "$HOOKS_SRC"/*.hook; do
            sudo install -Dm644 "$hook" "/etc/pacman.d/hooks/$(basename "$hook")"
            info "Installed: $(basename "$hook")"
        done
        success "Hooks installed"
    else
        warn "No hooks found in packages/hooks/"
    fi
fi

# ------------------------------------------------------------------
# 5. Dotfiles
# ------------------------------------------------------------------
if [[ $_do_dotfiles == true ]]; then
    step "Dotfiles"
    bash "$REPO_ROOT/lib/symlink.sh"
    success "Dotfiles linked"
fi

# ------------------------------------------------------------------
# 6. Fish as default shell
# ------------------------------------------------------------------
if [[ $_do_shell == true ]]; then
    step "Default shell"
    FISH_BIN="$(command -v fish 2>/dev/null || true)"
    if [[ -z "$FISH_BIN" ]]; then
        warn "fish not found — install it first (it should be in apps.conf)"
    elif [[ "$(getent passwd "$USER" | cut -d: -f7)" == "$FISH_BIN" ]]; then
        info "fish is already the default shell"
    else
        chsh -s "$FISH_BIN"
        success "Default shell set to fish"
    fi
fi

# ------------------------------------------------------------------
# Done
# ------------------------------------------------------------------
echo ""
success "Post-install complete."
echo "  Log out and back in (or reboot) to start the Hyprland session."
