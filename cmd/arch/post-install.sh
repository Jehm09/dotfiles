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
# sudo_keepalive is deliberately NOT called here: it would prompt for a password
# before the flags are even parsed, so `--help` and the desktop validation could
# not run without one. It is started further down, once we know work will happen.

# ------------------------------------------------------------------
# Defaults
# ------------------------------------------------------------------
_do_multilib=true
_do_aur_helper=true
_aur_helper="paru"        # paru | yay
_do_desktop=true
# Which desktop this machine gets. No default on purpose: the two profiles are
# mutually exclusive and every step below (packages, dotfiles, session) follows
# this one choice. Set with --hyprland / --kde, or 'd' in the menu.
_desktop=""
_do_apps=true
_do_greeter=true
_do_hooks=true
_do_dotfiles=true
_do_shell=true
_do_hwfix=true

_flag_noninteractive=false

# ------------------------------------------------------------------
# Parse flags
# ------------------------------------------------------------------
for arg in "$@"; do
    case "$arg" in
        --all)
            _flag_noninteractive=true
            ;;
        --hyprland) _desktop="hyprland" ;;
        --kde)      _desktop="kde"      ;;
        --dotfiles)
            _do_multilib=false; _do_aur_helper=false
            _do_desktop=false; _do_apps=false; _do_greeter=false
            _do_hooks=false; _do_shell=false; _do_hwfix=false
            _flag_noninteractive=true
            ;;
        --pkgs)
            _do_multilib=false; _do_greeter=false
            _do_hooks=false; _do_dotfiles=false; _do_shell=false; _do_hwfix=false
            _flag_noninteractive=true
            ;;
        --desktop-only)
            # Just the desktop: its packages plus its config. Useful to add or
            # switch the desktop on a machine that is already set up.
            _do_multilib=false; _do_aur_helper=false
            _do_apps=false; _do_greeter=false
            _do_hooks=false; _do_shell=false; _do_hwfix=false
            _flag_noninteractive=true
            ;;
        -h|--help)
            cat <<EOF
Usage: setup post <--hyprland|--kde> [options]

Desktop (required — pick one):
    --hyprland     Hyprland + Quickshell: deps-hyprland.conf + deps-quickshell.conf,
                   dotfiles from dots/common + dots/hyprland
    --kde          KDE Plasma: deps-kde.conf, dots/common, and the copy-managed
                   dots/kde profile applied with 'setup kde apply'

Options:
    --all            Run all components without prompting
    --dotfiles       Only link dotfiles (~/.config symlinks)
    --pkgs           Only install AUR helper + all packages
    --desktop-only   Only the chosen desktop: its packages + its config
    -h, --help       Show this help

To undo dotfiles only:
    setup dotfiles <hyprland|kde> --unlink

Interactive mode (default, no flags):
    A menu lets you pick the desktop and toggle each component before confirming.
EOF
            exit 0
            ;;
    esac
done

# ------------------------------------------------------------------
# Interactive menu
# ------------------------------------------------------------------
_desktop_label() {
    case "$_desktop" in
        hyprland) echo "hyprland  (deps-hyprland.conf + deps-quickshell.conf)" ;;
        kde)      echo "kde       (deps-kde.conf + perfil dots/kde)"           ;;
        *)        echo "SIN ELEGIR — pulsa 'd'"                               ;;
    esac
}

_print_menu() {
    echo ""
    echo -e "${_CLR_BOLD}  Post-instalación${_CLR_RST}"
    echo ""
    printf "        Escritorio: %s\n" "$(_desktop_label)"
    echo ""
    printf "    [%s] 1  Multilib             (Steam y apps de 32 bits)\n" \
        "$([[ $_do_multilib    == true ]] && echo "x" || echo " ")"
    printf "    [%s] 2  AUR helper           (actualmente: %s)\n" \
        "$([[ $_do_aur_helper    == true ]] && echo "x" || echo " ")" "$_aur_helper"
    printf "    [%s] 3  Paquetes del escritorio elegido\n" \
        "$([[ $_do_desktop       == true ]] && echo "x" || echo " ")"
    printf "    [%s] 4  Apps                 (packages/apps.conf — official + AUR)\n" \
        "$([[ $_do_apps          == true ]] && echo "x" || echo " ")"
    printf "    [%s] 5  Greeter              (greetd + sysc-greet-hyprland + seatd)\n" \
        "$([[ $_do_greeter       == true ]] && echo "x" || echo " ")"
    printf "    [%s] 6  Pacman hooks         (packages/hooks/enabled/)\n" \
        "$([[ $_do_hooks         == true ]] && echo "x" || echo " ")"
    printf "    [%s] 7  Dotfiles             (~/.config, según el escritorio)\n" \
        "$([[ $_do_dotfiles      == true ]] && echo "x" || echo " ")"
    printf "    [%s] 8  Fish como shell por defecto\n" \
        "$([[ $_do_shell         == true ]] && echo "x" || echo " ")"
    printf "    [%s] 9  Fixes de hardware      (blacklist mouse Logitech + initramfs)\n" \
        "$([[ $_do_hwfix         == true ]] && echo "x" || echo " ")"
    echo ""
    echo "    d: elegir escritorio  |  Alternar: escribe números (ej: 3 5)"
    echo "    p/y: cambiar AUR helper  |  Enter: ejecutar  |  0: salir"
}

if [[ "$_flag_noninteractive" == false && -t 0 ]]; then
    _print_menu
    while true; do
        read -rp "  > " _sel
        [[ -z "$_sel" ]] && break
        for token in $_sel; do
            case "$token" in
                0) echo ""; info "Saliendo sin cambios."; exit 0 ;;
                1) [[ $_do_multilib     == true ]] && _do_multilib=false     || _do_multilib=true     ;;
                2) [[ $_do_aur_helper   == true ]] && _do_aur_helper=false   || _do_aur_helper=true   ;;
                3) [[ $_do_desktop      == true ]] && _do_desktop=false      || _do_desktop=true      ;;
                4) [[ $_do_apps         == true ]] && _do_apps=false         || _do_apps=true         ;;
                5) [[ $_do_greeter      == true ]] && _do_greeter=false      || _do_greeter=true      ;;
                6) [[ $_do_hooks        == true ]] && _do_hooks=false        || _do_hooks=true        ;;
                7) [[ $_do_dotfiles     == true ]] && _do_dotfiles=false     || _do_dotfiles=true     ;;
                8) [[ $_do_shell        == true ]] && _do_shell=false        || _do_shell=true        ;;
                9) [[ $_do_hwfix        == true ]] && _do_hwfix=false        || _do_hwfix=true        ;;
                # Cycles hyprland -> kde -> hyprland, so it also works as the
                # initial pick when nothing is set yet.
                d) [[ "$_desktop" == "hyprland" ]] && _desktop="kde" || _desktop="hyprland" ;;
                p) _aur_helper="paru" ;;
                y) _aur_helper="yay"  ;;
            esac
        done
        _print_menu
    done
    echo ""
fi

# ------------------------------------------------------------------
# The desktop choice drives packages, dotfiles and session config, so refuse to
# run any of those steps without it rather than silently guessing one.
# ------------------------------------------------------------------
if [[ -z "$_desktop" ]] \
   && { [[ $_do_desktop == true ]] || [[ $_do_dotfiles == true ]]; }; then
    error "No has elegido escritorio. Usa --hyprland o --kde (o 'd' en el menú)."
    exit 1
fi

# Everything below this point can need root, so ask once and keep it alive.
sudo_keepalive
trap sudo_stop_keepalive EXIT INT TERM

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
# 3. Desktop packages — whichever desktop was chosen
# ------------------------------------------------------------------
if [[ $_do_desktop == true ]]; then
    step "Desktop packages ($_desktop)"

    case "$_desktop" in
        hyprland) _pkg_files=(deps-hyprland.conf deps-quickshell.conf) ;;
        kde)      _pkg_files=(deps-kde.conf)                           ;;
    esac

    _helper="$(_find_aur_helper)"
    if [[ -z "$_helper" ]]; then
        warn "No AUR helper found — skipping desktop packages (enable step 2 to install one)"
    else
        mapfile -t _pkgs < <(
            for _f in "${_pkg_files[@]}"; do
                parse_packages "$REPO_ROOT/packages/$_f"
            done
        )
        if [[ ${#_pkgs[@]} -gt 0 ]]; then
            info "Installing ${#_pkgs[@]} desktop packages with $_helper..."
            "$_helper" -S --needed --noconfirm "${_pkgs[@]}"
            success "Desktop packages installed"
        else
            warn "No packages found in ${_pkg_files[*]}"
        fi
    fi
fi

# ------------------------------------------------------------------
# 3c. Hyprland-specific: pinned quickshell + Python venv
# ------------------------------------------------------------------
if [[ $_do_desktop == true && "$_desktop" == "hyprland" ]]; then
    step "Quickshell runtime"

    # quickshell comes from the commit end-4 pins, not from the AUR's
    # quickshell-git — see the note at the top of packages/deps-quickshell.conf.
    # This needs the upstream clone, so make sure it exists first.
    if [[ ! -d "${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles/upstream" ]]; then
        bash "$REPO_ROOT/cmd/lib/upstream.sh" sync
    fi
    bash "$REPO_ROOT/cmd/lib/upstream.sh" deps

    step "Python virtualenv for shell scripts"

    # hypr/hyprland/env.lua exports this path as ILLOGICAL_IMPULSE_VIRTUAL_ENV.
    # Wallpaper colour extraction, thumbnails and region detection all shell out
    # to it, and fail quietly when it is missing.
    _venv="$HOME/.local/state/quickshell/.venv"
    if ! command -v uv &>/dev/null; then
        warn "uv not installed — skipping the venv (colour and thumbnail scripts will fail)"
    else
        [[ -d "$_venv" ]] || uv venv "$_venv"
        uv pip install --python "$_venv/bin/python" -r "$REPO_ROOT/packages/requirements.txt"
        success "venv ready at $_venv"
    fi
fi

# ------------------------------------------------------------------
# 3b. Plasma-specific session setup
#     Runs only when KDE is the chosen desktop: the wallet PAM hook and the
#     copy-managed dots/kde profile, which symlink.sh deliberately does not touch.
# ------------------------------------------------------------------
if [[ $_do_desktop == true && "$_desktop" == "kde" ]]; then
    step "KDE Plasma session"

    # KWallet auto-unlock at login.
    #
    # Without this KDE asks for the wallet password on every login. The greeter's
    # PAM stack already carries pam_gnome_keyring, but that only unlocks
    # gnome-keyring — KWallet needs its own module, which ships in kwallet-pam
    # (a plasma-meta dependency).
    #
    # It only works when the wallet password is the SAME as the login password.
    # If the wallet was created with a different one, change it in
    # KWalletManager -> Change Password.
    #
    # force_run is REQUIRED with greetd. Without it the module logs
    #   "pam_kwallet5: not a graphical session, skipping"
    # and never creates /run/user/<uid>/kwallet5.socket, so kwalletd6 ends up
    # being DBus-activated later without the key and prompts for the password.
    # greetd's PAM session is not flagged graphical at the point the module runs.
    _pam_greetd="/etc/pam.d/greetd"
    if [[ -f "$_pam_greetd" ]] && ! grep -q 'pam_kwallet5' "$_pam_greetd"; then
        info "Enabling KWallet auto-unlock (pam_kwallet5)..."
        sudo sed -i '/^auth.*pam_gnome_keyring\.so/a auth       optional     pam_kwallet5.so' "$_pam_greetd"
        sudo sed -i '/^session.*pam_gnome_keyring\.so/a session    optional     pam_kwallet5.so auto_start force_run' "$_pam_greetd"
        success "pam_kwallet5 added to $_pam_greetd"
    elif [[ -f "$_pam_greetd" ]] && grep -q 'pam_kwallet5.so auto_start$' "$_pam_greetd"; then
        info "Adding force_run to the existing pam_kwallet5 session line..."
        sudo sed -i 's|^\(session.*pam_kwallet5\.so auto_start\)$|\1 force_run|' "$_pam_greetd"
    fi

    info "Applying the KDE profile (dots/kde -> ~)..."
    bash "$REPO_ROOT/cmd/lib/kde.sh" apply

    # Make the new .desktop shortcut entries visible to kglobalaccel.
    command -v kbuildsycoca6 &>/dev/null && kbuildsycoca6 --noincremental &>/dev/null || true

    success "KDE configured — pick 'Plasma (Wayland)' at the login screen"
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
    step "Dotfiles ($_desktop)"
    # Any real dir/file displaced by a symlink is saved as <name>.backup.TIMESTAMP.
    # Undo with: setup dotfiles <hyprland|kde> --unlink
    bash "$REPO_ROOT/cmd/lib/symlink.sh" "$_desktop"
    success "Dotfiles linked  (undo: setup dotfiles $_desktop --unlink)"
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
# 9. Hardware fixes (Logitech mouse scroll wheel)
# ------------------------------------------------------------------
if [[ $_do_hwfix == true ]]; then
    step "Hardware fixes (Logitech mouse)"

    _modprobe_src="$REPO_ROOT/packages/modprobe/blacklist-hid-logitech-hidpp.conf"
    _modprobe_dst="/etc/modprobe.d/blacklist-hid-logitech-hidpp.conf"

    if [[ ! -f "$_modprobe_src" ]]; then
        warn "Missing $_modprobe_src — skipping Logitech mouse fix"
    elif sudo cmp -s "$_modprobe_src" "$_modprobe_dst" 2>/dev/null; then
        info "Logitech hid_logitech_hidpp blacklist already installed"
    else
        info "Installing hid_logitech_hidpp blacklist to $_modprobe_dst..."
        sudo install -Dm644 "$_modprobe_src" "$_modprobe_dst"
        info "Rebuilding initramfs (mkinitcpio -P)..."
        sudo mkinitcpio -P
        success "Logitech mouse fix installed — reboot for the scroll wheel to work"
    fi
fi

# ------------------------------------------------------------------
# Done
# ------------------------------------------------------------------
echo ""
success "Post-install complete."
echo "  Log out and back in (or reboot) to start the Hyprland session."
