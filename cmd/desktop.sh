#!/usr/bin/env bash
# Hyprland desktop installer for an existing Arch Linux system.
# Run as your regular user (with sudo access) from the dotfiles root.
#
# Usage:
#   ./setup desktop              Interactive component selection
#   ./setup desktop --all        Install everything without prompting
#   ./setup desktop --skip-aur   Skip AUR packages
#   ./setup desktop --dotfiles   Only link dotfiles

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

source "$REPO_ROOT/lib/utils.sh"

PACKAGES_DIR="$REPO_ROOT/packages"

# ------------------------------------------------------------------
# Defaults
# ------------------------------------------------------------------
_do_desktop=true
_do_apps=true
_do_aur=true
_do_services=true
_do_discord=true
_do_shell=true
_do_dotfiles=true

_flag_noninteractive=false

# ------------------------------------------------------------------
# Parse flags
# ------------------------------------------------------------------
for arg in "$@"; do
    case "$arg" in
        --all)
            _flag_noninteractive=true
            ;;
        --skip-aur)
            _do_aur=false
            _flag_noninteractive=true
            ;;
        --skip-discord)
            _do_discord=false
            _flag_noninteractive=true
            ;;
        --dotfiles)
            _do_desktop=false; _do_apps=false; _do_aur=false
            _do_services=false; _do_discord=false; _do_shell=false
            _flag_noninteractive=true
            ;;
        -h|--help)
            cat <<EOF
Usage: ./setup desktop [options]

Options:
    --all          Install all components (including hardware drivers)
    --skip-aur     Skip AUR package installation
    --skip-discord Skip Discord + Equicord patching
    --dotfiles     Only link dotfiles (~/.config)
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
    echo -e "${_CLR_BOLD}Select components to install:${_CLR_RST}"
    echo ""
    printf "  [%s] 1  Desktop packages   (Hyprland, greetd, fonts, theming)\n" "$( [[ $_do_desktop  == true ]] && echo "x" || echo " ")"
    printf "  [%s] 2  Personal apps      (fish, nautilus, mpv, yazi...)\n"    "$( [[ $_do_apps     == true ]] && echo "x" || echo " ")"
    printf "  [%s] 3  AUR packages       (quickshell, asdf-vm, vscode, brave...)\n" "$( [[ $_do_aur  == true ]] && echo "x" || echo " ")"
    printf "  [%s] 4  Services           (seatd, greetd, gnome-keyring, polkit)\n"  "$( [[ $_do_services == true ]] && echo "x" || echo " ")"
    printf "  [%s] 5  Discord + Equicord\n"                                         "$( [[ $_do_discord  == true ]] && echo "x" || echo " ")"
    printf "  [%s] 6  Fish as default shell\n"                                      "$( [[ $_do_shell    == true ]] && echo "x" || echo " ")"
    printf "  [%s] 7  Dotfiles           (~/.config symlinks)\n"                    "$( [[ $_do_dotfiles == true ]] && echo "x" || echo " ")"
    echo ""
    echo "  Enter numbers to toggle (e.g. 4 6), or press Enter to confirm:"
}

if [[ "$_flag_noninteractive" == false && -t 0 ]]; then
    _print_menu
    while true; do
        read -rp "> " _sel
        [[ -z "$_sel" ]] && break
        for n in $_sel; do
            case "$n" in
                1) [[ $_do_desktop  == true ]] && _do_desktop=false  || _do_desktop=true  ;;
                2) [[ $_do_apps     == true ]] && _do_apps=false      || _do_apps=true     ;;
                3) [[ $_do_aur      == true ]] && _do_aur=false       || _do_aur=true      ;;
                4) [[ $_do_services == true ]] && _do_services=false  || _do_services=true ;;
                5) [[ $_do_discord  == true ]] && _do_discord=false   || _do_discord=true  ;;
                6) [[ $_do_shell    == true ]] && _do_shell=false     || _do_shell=true    ;;
                7) [[ $_do_dotfiles == true ]] && _do_dotfiles=false  || _do_dotfiles=true ;;
            esac
        done
        _print_menu
    done
    echo ""
fi

# ------------------------------------------------------------------
# Safety + sudo keepalive
# ------------------------------------------------------------------
prevent_root
sudo_keepalive
trap sudo_stop_keepalive EXIT INT TERM

# ------------------------------------------------------------------
# 1. Multilib (needed before any pacman install)
# ------------------------------------------------------------------
if [[ $_do_desktop == true || $_do_apps == true || $_do_aur == true ]]; then
    multilib_enable
fi

# ------------------------------------------------------------------
# 2. Desktop packages
# ------------------------------------------------------------------
if [[ $_do_desktop == true ]]; then
    step "Desktop packages"
    mapfile -t _pkgs < <(parse_packages "$PACKAGES_DIR/desktop.conf")
    sudo pacman -S --needed --noconfirm "${_pkgs[@]}"
    success "Desktop packages installed"
fi

# ------------------------------------------------------------------
# 3. Personal apps
# ------------------------------------------------------------------
if [[ $_do_apps == true ]]; then
    step "Personal apps"
    mapfile -t _pkgs < <(parse_packages "$PACKAGES_DIR/apps.conf")
    sudo pacman -S --needed --noconfirm "${_pkgs[@]}"
    success "Personal apps installed"
fi

# ------------------------------------------------------------------
# 4. paru + AUR packages
# ------------------------------------------------------------------
if [[ $_do_aur == true ]]; then
    step "paru (AUR helper)"
    if command -v paru &>/dev/null; then
        info "paru already installed, skipping"
    else
        PARU_TMP=$(mktemp -d)
        trap 'rm -rf "$PARU_TMP"' EXIT
        git clone https://aur.archlinux.org/paru.git "$PARU_TMP"
        (cd "$PARU_TMP" && makepkg -si --noconfirm)
        success "paru installed"
    fi

    step "AUR packages"
    mapfile -t _pkgs < <(parse_packages "$PACKAGES_DIR/aur.conf")
    paru -S --needed --noconfirm "${_pkgs[@]}"
    success "AUR packages installed"
fi

# ------------------------------------------------------------------
# 5. Services
# ------------------------------------------------------------------
if [[ $_do_services == true ]]; then
    step "Services"

    info "Enabling seatd..."
    sudo systemctl enable --now seatd
    sudo usermod -aG seat "$USER"

    info "Configuring greetd..."
    sudo mkdir -p /etc/greetd
    sudo tee /etc/greetd/config.toml > /dev/null <<'EOF'
[terminal]
vt = 1

[default_session]
# sysc-greet-hyprland: graphical console greeter for greetd, Hyprland variant.
# Source: https://github.com/b1rger/sysc-greet
command = "sysc-greet-hyprland"
user = "greeter"
EOF
    sudo systemctl enable greetd

    # gnome-keyring PAM integration (auto-unlock on login)
    _pam_login="/etc/pam.d/login"
    if [[ -f "$_pam_login" ]] && ! grep -q 'pam_gnome_keyring' "$_pam_login"; then
        info "Configuring gnome-keyring PAM integration..."
        sudo sed -i '/^auth.*pam_unix\.so/a auth       optional     pam_gnome_keyring.so' "$_pam_login"
        sudo sed -i '/^session.*pam_unix\.so/a session    optional     pam_gnome_keyring.so auto_start' "$_pam_login"
    fi

    # NVIDIA Wayland environment variables
    if lspci 2>/dev/null | grep -qi nvidia; then
        info "Writing NVIDIA Wayland environment variables..."
        sudo tee /etc/environment > /dev/null <<'EOF'
# NVIDIA Wayland compatibility
LIBVA_DRIVER_NAME=nvidia
GBM_BACKEND=nvidia-drm
__GLX_VENDOR_LIBRARY_NAME=nvidia
WLR_NO_HARDWARE_CURSORS=1

# Session type
XDG_SESSION_TYPE=wayland

# Qt: Wayland backend
QT_QPA_PLATFORM=wayland
QT_WAYLAND_DISABLE_WINDOWDECORATION=1

# GTK: prefer Wayland, fall back to X11
GDK_BACKEND=wayland,x11

# Firefox, Electron apps (VSCode, Discord, etc.)
MOZ_ENABLE_WAYLAND=1
NIXOS_OZONE_WL=1
EOF
    fi

    # XDG desktop portals
    sudo systemctl --global enable xdg-desktop-portal || true

    # pacman hooks
    info "Installing pacman hooks..."
    sudo mkdir -p /etc/pacman.d/hooks
    for hook in "$PACKAGES_DIR/hooks/"*.hook; do
        [[ -f "$hook" ]] || continue
        sudo install -Dm644 "$hook" "/etc/pacman.d/hooks/$(basename "$hook")"
    done

    success "Services configured"
fi

# ------------------------------------------------------------------
# 6. Discord + Equicord (packages come from aur.conf; this applies the patch)
# ------------------------------------------------------------------
if [[ $_do_discord == true ]]; then
    step "Discord + Equicord"
    if command -v Equilotl &>/dev/null && [[ -d /opt/discord ]]; then
        sudo Equilotl -install -location /opt/discord
        sudo Equilotl -install-openasar -location /opt/discord
        success "Equicord applied"
    else
        warn "Discord not found at /opt/discord — ensure AUR packages are installed first"
    fi
fi

# ------------------------------------------------------------------
# 7. Fish as default shell
# ------------------------------------------------------------------
if [[ $_do_shell == true ]]; then
    step "Default shell"
    _fish_bin="$(command -v fish 2>/dev/null || true)"
    if [[ -z "$_fish_bin" ]]; then
        warn "fish not found, skipping shell change"
    elif [[ "$SHELL" != "$_fish_bin" ]]; then
        info "Setting fish as default shell..."
        chsh -s "$_fish_bin"
    else
        info "fish is already the default shell"
    fi

    _asdf_conf="${XDG_CONFIG_HOME:-$HOME/.config}/fish/conf.d/asdf.fish"
    if [[ ! -f "$_asdf_conf" ]]; then
        info "Configuring asdf-vm for fish..."
        mkdir -p "$(dirname "$_asdf_conf")"
        echo 'source /opt/asdf-vm/asdf.fish' > "$_asdf_conf"
    fi
fi

# ------------------------------------------------------------------
# 8. Dotfiles
# ------------------------------------------------------------------
if [[ $_do_dotfiles == true ]]; then
    step "Dotfiles"
    if command -v gsettings &>/dev/null; then
        gsettings set com.github.stunkymonkey.nautilus-open-any-terminal terminal kitty 2>/dev/null || true
    fi
    bash "$REPO_ROOT/lib/symlink.sh"
    success "Dotfiles linked"
fi

# ------------------------------------------------------------------
# Done
# ------------------------------------------------------------------
echo ""
success "Desktop setup complete."
echo "  Log out and back in (or reboot) to start the Hyprland session."
[[ $_do_shell == true ]] && echo "  NOTE: Re-login for the new default shell (fish) to take effect." || true
