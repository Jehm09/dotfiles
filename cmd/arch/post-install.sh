#!/usr/bin/env bash
# Post-install setup — run after first boot into the new Arch system.
# Handles everything archinstall cannot: multilib, AUR helper, AUR packages,
# greeter (greetd + sysc-greet-hyprland), pacman hooks, dotfiles, and default shell.
#
# Usage:
#   setup post              Interactive component selection (default)
#   setup post --all        Run everything without prompting
#   setup post --dotfiles   Only link dotfiles
#   setup post --aur        Only install AUR helper + AUR packages

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$REPO_ROOT/cmd/lib/utils.sh"

prevent_root
sudo_keepalive
trap sudo_stop_keepalive EXIT INT TERM

# ------------------------------------------------------------------
# Defaults
# ------------------------------------------------------------------
_do_multilib=true
_do_aur_helper=true
_aur_helper="paru"        # paru | yay
_do_desktop_pkgs=true
_do_apps=true
_do_greeter=true
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
            _do_desktop_pkgs=false; _do_apps=false; _do_greeter=false
            _do_hooks=false; _do_shell=false
            _flag_noninteractive=true
            ;;
        --pkgs)
            _do_multilib=false; _do_greeter=false
            _do_hooks=false; _do_dotfiles=false; _do_shell=false
            _flag_noninteractive=true
            ;;
        -h|--help)
            cat <<EOF
Usage: setup post [options]

Options:
    --all          Run all components without prompting
    --dotfiles     Only link dotfiles (~/.config symlinks)
    --pkgs         Only install AUR helper + all packages
    -h, --help     Show this help

To undo dotfiles only:
    setup dotfiles --unlink

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
    echo -e "${_CLR_BOLD}  Post-instalación — selecciona componentes:${_CLR_RST}"
    echo ""
    printf "    [%s] 1  Multilib             (Steam y apps de 32 bits)\n" \
        "$([[ $_do_multilib    == true ]] && echo "x" || echo " ")"
    printf "    [%s] 2  AUR helper           (actualmente: %s)\n" \
        "$([[ $_do_aur_helper    == true ]] && echo "x" || echo " ")" "$_aur_helper"
    printf "    [%s] 3  Desktop packages     (deps-hyprland.conf + deps-quickshell.conf)\n" \
        "$([[ $_do_desktop_pkgs  == true ]] && echo "x" || echo " ")"
    printf "    [%s] 4  Apps                 (packages/apps.conf — official + AUR)\n" \
        "$([[ $_do_apps          == true ]] && echo "x" || echo " ")"
    printf "    [%s] 5  Greeter              (greetd + sysc-greet-hyprland + seatd)\n" \
        "$([[ $_do_greeter       == true ]] && echo "x" || echo " ")"
    printf "    [%s] 6  Pacman hooks         (packages/hooks/enabled/)\n" \
        "$([[ $_do_hooks         == true ]] && echo "x" || echo " ")"
    printf "    [%s] 7  Dotfiles             (~/.config symlinks)\n" \
        "$([[ $_do_dotfiles      == true ]] && echo "x" || echo " ")"
    printf "    [%s] 8  Fish como shell por defecto\n" \
        "$([[ $_do_shell         == true ]] && echo "x" || echo " ")"
    echo ""
    echo "    Alternar: escribe números (ej: 3 5)  |  p/y: cambiar AUR helper"
    echo "    Enter: ejecutar  |  0: salir sin hacer nada"
}

if [[ "$_flag_noninteractive" == false && -t 0 ]]; then
    _print_menu
    while true; do
        read -rp "  > " _sel
        [[ -z "$_sel" ]] && break
        for token in $_sel; do
            case "$token" in
                0) echo ""; info "Saliendo sin cambios."; exit 0 ;;
                1) [[ $_do_multilib      == true ]] && _do_multilib=false      || _do_multilib=true      ;;
                2) [[ $_do_aur_helper   == true ]] && _do_aur_helper=false   || _do_aur_helper=true   ;;
                3) [[ $_do_desktop_pkgs == true ]] && _do_desktop_pkgs=false || _do_desktop_pkgs=true ;;
                4) [[ $_do_apps         == true ]] && _do_apps=false         || _do_apps=true         ;;
                5) [[ $_do_greeter      == true ]] && _do_greeter=false      || _do_greeter=true      ;;
                6) [[ $_do_hooks        == true ]] && _do_hooks=false        || _do_hooks=true        ;;
                7) [[ $_do_dotfiles     == true ]] && _do_dotfiles=false     || _do_dotfiles=true     ;;
                8) [[ $_do_shell        == true ]] && _do_shell=false        || _do_shell=true        ;;
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
# helper: resolve paru or yay
# ------------------------------------------------------------------
_find_aur_helper() {
    for h in paru yay; do
        command -v "$h" &>/dev/null && { echo "$h"; return; }
    done
}

# ------------------------------------------------------------------
# 3. Desktop packages (Hyprland + Quickshell)
# ------------------------------------------------------------------
if [[ $_do_desktop_pkgs == true ]]; then
    step "Desktop packages (Hyprland + Quickshell)"

    _helper="$(_find_aur_helper)"
    if [[ -z "$_helper" ]]; then
        warn "No AUR helper found — skipping desktop packages (enable step 2 to install one)"
    else
        mapfile -t _pkgs < <(
            parse_packages "$REPO_ROOT/packages/deps-hyprland.conf"
            parse_packages "$REPO_ROOT/packages/deps-quickshell.conf"
        )
        if [[ ${#_pkgs[@]} -gt 0 ]]; then
            info "Installing ${#_pkgs[@]} desktop packages with $_helper..."
            "$_helper" -S --needed --noconfirm "${_pkgs[@]}"
            success "Desktop packages installed"
        else
            warn "No packages found in deps-hyprland.conf / deps-quickshell.conf"
        fi
    fi
fi

# ------------------------------------------------------------------
# 4. Apps (official + AUR — full apps.conf)
# ------------------------------------------------------------------
if [[ $_do_apps == true ]]; then
    step "Apps (apps.conf)"

    _helper="$(_find_aur_helper)"
    if [[ -z "$_helper" ]]; then
        warn "No AUR helper found — skipping apps (enable step 2 to install one)"
    else
        mapfile -t _pkgs < <(parse_packages "$REPO_ROOT/packages/apps.conf")
        if [[ ${#_pkgs[@]} -gt 0 ]]; then
            info "Installing ${#_pkgs[@]} packages with $_helper..."
            "$_helper" -S --needed --noconfirm "${_pkgs[@]}"
            success "Apps installed"
        else
            warn "No packages found in apps.conf"
        fi
    fi
fi

# ------------------------------------------------------------------
# 5. Greeter (greetd + sysc-greet-hyprland + seatd)
# ------------------------------------------------------------------
if [[ $_do_greeter == true ]]; then
    step "Greeter (greetd + sysc-greet-hyprland)"

    # greetd desde repos oficiales
    sudo pacman -S --needed --noconfirm greetd

    # sysc-greet-hyprland desde AUR
    _helper=""
    for h in paru yay; do command -v "$h" &>/dev/null && { _helper="$h"; break; }; done
    if [[ -z "$_helper" ]]; then
        warn "No AUR helper found — skipping sysc-greet-hyprland (enable step 2 first)"
    else
        "$_helper" -S --needed --noconfirm sysc-greet-hyprland
    fi

    # Deshabilitar sddm si está activo (instalado por archinstall)
    if systemctl is-enabled sddm &>/dev/null 2>&1; then
        info "Disabling sddm..."
        sudo systemctl disable sddm
    fi

    info "Enabling seatd..."
    sudo systemctl enable --now seatd
    sudo usermod -aG seat "$USER"

    info "Configuring greetd..."
    sudo mkdir -p /etc/greetd
    sudo tee /etc/greetd/config.toml > /dev/null <<'TOML'
[terminal]
vt = 1

[default_session]
# sysc-greet-hyprland: graphical console greeter for greetd, Hyprland variant.
# Source: https://github.com/b1rger/sysc-greet
command = "sysc-greet-hyprland"
user = "greeter"
TOML
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
        sudo tee /etc/environment > /dev/null <<'ENV'
XDG_SESSION_TYPE=wayland
LIBVA_DRIVER_NAME=nvidia
GBM_BACKEND=nvidia-drm
__GLX_VENDOR_LIBRARY_NAME=nvidia
WLR_NO_HARDWARE_CURSORS=1
QT_QPA_PLATFORM=wayland
QT_WAYLAND_DISABLE_WINDOWDECORATION=1
GDK_BACKEND=wayland,x11
MOZ_ENABLE_WAYLAND=1
NIXOS_OZONE_WL=1
ENV
    fi

    # XDG desktop portals
    sudo systemctl --global enable xdg-desktop-portal || true

    success "Greeter configured"
fi

# ------------------------------------------------------------------
# 6. Pacman hooks
# ------------------------------------------------------------------
if [[ $_do_hooks == true ]]; then
    step "Pacman hooks"
    HOOKS_SRC="$REPO_ROOT/packages/hooks/enabled"
    if [[ -d "$HOOKS_SRC" ]] && compgen -G "$HOOKS_SRC/*.hook" > /dev/null; then
        sudo mkdir -p /etc/pacman.d/hooks
        for hook in "$HOOKS_SRC"/*.hook; do
            sudo install -Dm644 "$hook" "/etc/pacman.d/hooks/$(basename "$hook")"
            info "Installed: $(basename "$hook")"
        done
        success "Hooks installed"
    else
        warn "No active hooks in packages/hooks/enabled/ — move hooks there to enable them"
    fi
fi

# ------------------------------------------------------------------
# 7. Dotfiles
# ------------------------------------------------------------------
if [[ $_do_dotfiles == true ]]; then
    step "Dotfiles"
    # Any real dir/file displaced by a symlink is saved as <name>.backup.TIMESTAMP.
    # Undo with: setup dotfiles --unlink
    bash "$REPO_ROOT/cmd/lib/symlink.sh"
    success "Dotfiles linked  (undo: setup dotfiles --unlink)"
fi

# ------------------------------------------------------------------
# 8. Fish as default shell
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

    _asdf_conf="${XDG_CONFIG_HOME:-$HOME/.config}/fish/conf.d/asdf.fish"
    if [[ ! -f "$_asdf_conf" ]]; then
        info "Configuring asdf-vm for fish..."
        mkdir -p "$(dirname "$_asdf_conf")"
        echo 'source /opt/asdf-vm/asdf.fish' > "$_asdf_conf"
    fi
fi

# ------------------------------------------------------------------
# Done
# ------------------------------------------------------------------
echo ""
success "Post-install complete."
echo "  Log out and back in (or reboot) to start the Hyprland session."
