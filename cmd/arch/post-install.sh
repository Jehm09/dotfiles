#!/usr/bin/env bash
# Post-install setup — run after first boot into the new Arch system.
# Handles everything archinstall cannot.
#
# Steps, in order:
#   1   Multilib          enable the [multilib] repo (Steam, 32-bit apps)
#   2   AUR helper        install paru (or yay)
#   3   Desktop packages  deps-hyprland+deps-quickshell, or deps-kde
#   3b  Plasma session    KWallet PAM hook + apply the copy-managed dots/kde   [kde]
#   3c  Quickshell        pinned quickshell build + Python venv          [hyprland]
#   4   Apps              everything in apps.conf (official + AUR)
#   5   Display manager   SDDM + sddm-astronaut-theme (hyprland_kath variant)
#   6   Pacman hooks      install packages/hooks/enabled/ to /etc/pacman.d/hooks
#   7   Dotfiles          symlink ~/.config for the chosen desktop
#   8   Shell             set fish as the login shell
#   9   Hardware fixes    Logitech mouse module blacklist + initramfs rebuild
#
# Steps 3b and 3c are mutually exclusive: they follow the desktop choice, which
# is required and has no default.
#
# Usage:
#   setup post --hyprland        Interactive component selection
#   setup post --all --hyprland  Run everything without prompting
#   setup post --dotfiles        Only link dotfiles
#   setup post --pkgs            Only AUR helper + all packages
#   setup post --desktop-only    Only the chosen desktop's packages + config
#   setup post --help            Full flag reference

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
        *)
            # Without this a typo like --hyprlnad would be ignored silently and
            # the run would stop later with a confusing "no desktop chosen".
            error "Unknown option: $arg"
            error "See: setup post --help"
            exit 1
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
    printf "    [%s] 5  Display manager     (SDDM + tema astronaut)\n" \
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
    # This edits the display manager's own PAM stack, so it has to follow whichever
    # one is in use. SDDM is the current greeter; /etc/pam.d/greetd is still
    # handled in case greetd is ever re-enabled as the fallback.
    #
    # force_run was REQUIRED with greetd: without it the module logged
    #   "pam_kwallet5: not a graphical session, skipping"
    # and never created /run/user/<uid>/kwallet5.socket, so kwalletd6 got
    # DBus-activated later without the key and prompted for the password. SDDM
    # does flag its session graphical, but force_run is harmless there and keeps
    # both stacks identical.
    for _pam_dm in /etc/pam.d/sddm /etc/pam.d/greetd; do
        [[ -f "$_pam_dm" ]] || continue
        if ! grep -q 'pam_kwallet5' "$_pam_dm"; then
            info "Enabling KWallet auto-unlock (pam_kwallet5) in $_pam_dm..."
            sudo sed -i '/^auth.*pam_gnome_keyring\.so/a auth       optional     pam_kwallet5.so' "$_pam_dm"
            sudo sed -i '/^session.*pam_gnome_keyring\.so/a session    optional     pam_kwallet5.so auto_start force_run' "$_pam_dm"
            success "pam_kwallet5 added to $_pam_dm"
        elif grep -q 'pam_kwallet5.so auto_start$' "$_pam_dm"; then
            info "Adding force_run to the existing pam_kwallet5 session line in $_pam_dm..."
            sudo sed -i 's|^\(session.*pam_kwallet5\.so auto_start\)$|\1 force_run|' "$_pam_dm"
        fi
    done

    info "Applying the KDE profile (dots/kde -> ~)..."
    bash "$REPO_ROOT/cmd/lib/kde.sh" apply

    # Make the new .desktop shortcut entries visible to kglobalaccel.
    command -v kbuildsycoca6 &>/dev/null && kbuildsycoca6 --noincremental &>/dev/null || true

    success "KDE configured — pick 'Plasma (Wayland)' at the login screen"
fi

# ------------------------------------------------------------------
# 3c. Hyprland-specific: pinned quickshell + Python venv
#     Runs only when Hyprland is the chosen desktop. Both pieces are things the
#     plain package lists cannot express.
# ------------------------------------------------------------------
if [[ $_do_desktop == true && "$_desktop" == "hyprland" ]]; then
    step "Quickshell runtime (pinned build)"

    # quickshell is built from the commit end-4 pins, not from the AUR's
    # quickshell-git, which tracks master and breaks the shell on a bad day.
    # See the note at the top of packages/deps-quickshell.conf.
    # The PKGBUILD lives in the upstream clone, so ensure that exists first.
    if [[ ! -d "${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles/upstream" ]]; then
        bash "$REPO_ROOT/cmd/lib/upstream.sh" sync
    fi
    bash "$REPO_ROOT/cmd/lib/upstream.sh" deps

    step "Python virtualenv for the shell's helper scripts"

    # hypr/hyprland/env.lua exports this path as ILLOGICAL_IMPULSE_VIRTUAL_ENV.
    # Wallpaper colour extraction, thumbnail generation and region detection all
    # shell out to it, and fail quietly when it is missing.
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
# 5. Display manager (SDDM + sddm-astronaut-theme)
# ------------------------------------------------------------------
if [[ $_do_greeter == true ]]; then
    step "Display manager (SDDM + astronaut theme)"

    _helper="$(_find_aur_helper)"
    if [[ -z "$_helper" ]]; then
        warn "No AUR helper found — skipping the display manager (run step 2 first)"
    else
        mapfile -t _greeter_pkgs < <(parse_packages "$REPO_ROOT/packages/deps-greeter.conf")
        info "Installing ${#_greeter_pkgs[@]} display manager packages..."
        "$_helper" -S --needed --noconfirm "${_greeter_pkgs[@]}"

        # Theme variant and screen size.
        #
        # Both live in files the sddm-astronaut-theme package owns, so an upgrade
        # resets them. packages/hooks/enabled/sddm-astronaut-theme.hook re-applies
        # exactly these two edits afterwards — keep the values in sync.
        _theme_dir="/usr/share/sddm/themes/sddm-astronaut-theme"
        if [[ -d "$_theme_dir" ]]; then
            info "Selecting the hyprland_kath variant..."
            sudo sed -i 's|^ConfigFile=.*|ConfigFile=Themes/hyprland_kath.conf|' \
                "$_theme_dir/metadata.desktop"
            sudo sed -i -e 's|^ScreenWidth=.*|ScreenWidth="2560"|' \
                        -e 's|^ScreenHeight=.*|ScreenHeight="1440"|' \
                "$_theme_dir/Themes/hyprland_kath.conf"
        else
            warn "Theme not found at $_theme_dir — skipping the variant selection"
        fi

        info "Configuring SDDM..."
        sudo mkdir -p /etc/sddm.conf.d

        # .conf.d drop-ins rather than /etc/sddm.conf: the latter is a pacman
        # .pacnew magnet, and drop-ins keep our settings separate from defaults.
        sudo tee /etc/sddm.conf.d/10-theme.conf > /dev/null <<'CONF'
# Managed by setup post. See packages/deps-greeter.conf.
[Theme]
Current=sddm-astronaut-theme
CONF

        # The theme's login field expects the Qt virtual keyboard to be available.
        sudo tee /etc/sddm.conf.d/20-virtualkbd.conf > /dev/null <<'CONF'
# Managed by setup post.
[General]
InputMethod=qtvirtualkeyboard
CONF

        # Wayland greeter: this box runs Hyprland and Plasma Wayland, and the X11
        # greeter would pull in a whole Xorg session just to draw the login form.
        sudo tee /etc/sddm.conf.d/30-wayland.conf > /dev/null <<'CONF'
# Managed by setup post.
[General]
DisplayServer=wayland
GreeterEnvironment=QT_WAYLAND_SHELL_INTEGRATION=layer-shell
CONF

        # greetd was the previous display manager. Only one may be enabled: the
        # display-manager.service symlink points at whichever won.
        if systemctl is-enabled greetd &>/dev/null; then
            info "Disabling greetd (kept installed as a fallback)..."
            sudo systemctl disable greetd
        fi
        sudo systemctl enable sddm

        success "SDDM enabled — greetd left installed but disabled"
    fi

    # gnome-keyring PAM integration (auto-unlock on login).
    # /etc/pam.d/login covers TTY logins; /etc/pam.d/sddm covers the graphical
    # one and is a separate stack, so both need the module.
    for _pam in /etc/pam.d/login /etc/pam.d/sddm; do
        if [[ -f "$_pam" ]] && ! grep -q 'pam_gnome_keyring' "$_pam"; then
            info "Configuring gnome-keyring PAM integration in $_pam..."
            sudo sed -i '/^auth.*pam_unix\.so/a auth       optional     pam_gnome_keyring.so' "$_pam"
            sudo sed -i '/^session.*pam_unix\.so/a session    optional     pam_gnome_keyring.so auto_start' "$_pam"
        fi
    done

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
