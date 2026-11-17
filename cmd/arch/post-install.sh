#!/usr/bin/env bash
# Post-install setup — run after first boot into the new Arch system.
# Handles everything archinstall cannot.
#
# This is the only script you re-run. 'setup install' is the one-off that runs
# archinstall from the live ISO; everything else lives here, and can be run
# whole, a step at a time, or again later.
#
# Steps run in this order, and the order is the point: each assumes the ones
# above it are done. Skipping one means "already handled some other way".
#
#   1   multilib   enable the [multilib] repo (Steam, 32-bit apps)
#   2   aur        install yay / paru / both — steps 3+ install through it
#   3   desktop    deps-hyprland + deps-quickshell, pinned quickshell build + Python venv
#   4   apps       everything in apps.conf (official + AUR)
#   5   greeter    SDDM + astronaut theme, or greetd + sysc-greet
#   6   hooks      install packages/hooks/enabled/ to /etc/pacman.d/hooks
#   7   dotfiles   symlink ~/.config — dots/common + dots/hyprland
#   8   shell      set fish as the login shell
#   9   hwfix      Logitech mouse module blacklist + initramfs rebuild
#
# Usage:
#   setup post                        Pick steps in a menu
#   setup post --all                  Everything, no prompts
#   setup post --only greeter         One step
#   setup post --skip apps,hwfix      Everything but those
#   setup post --help                 Full flag reference

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$REPO_ROOT/cmd/lib/utils.sh"

prevent_root
# sudo_keepalive is deliberately NOT called here: it would prompt for a password
# before the flags are even parsed, so `--help` could not run without one. It is started further down, once we know work will happen.

# ------------------------------------------------------------------
# Steps
# ------------------------------------------------------------------
# Every step has a name. --only and --skip take those names, the menu shows
# them, and each numbered section below is guarded by its _do_<name> variable.
# Adding a step means adding it here, to STEP_DESC, and to its own section.
STEPS=(multilib aur desktop apps greeter hooks dotfiles shell hwfix)

# Descriptions double as the menu labels. The order of STEPS above is the order
# things must happen in, and the numbers make that visible: each step assumes the
# ones above it are done. Skipping one is fine — it just means "I already have
# this handled some other way".
declare -A STEP_DESC=(
    [multilib]="1. base     [multilib] repo — Steam, 32-bit apps"
    [aur]="2. base     paru/yay — every step below installs through it"
    [desktop]="3. desktop  graphical stack — Hyprland/Quickshell"
    [apps]="4. apps     browsers, editors, games — apps.conf"
    [greeter]="5. login    SDDM, or greetd + sysc-greet"
    [hooks]="6. system   pacman hooks from hooks/enabled/"
    [dotfiles]="7. config   ~/.config — kitty, fish, fastfetch, hypr, quickshell"
    [shell]="8. config   fish as the login shell"
    [hwfix]="9. hardware Logitech mouse fix + initramfs"
)

# One label format for both the menu and --help, so they cannot drift.
_step_label() { printf '%-10s %s' "$1" "${STEP_DESC[$1]}"; }

# Which AUR helpers are already installed. Everything from step 3 down installs
# through one, so when there is none the AUR step stops being optional.
_installed_helpers() {
    local h
    for h in paru yay; do command -v "$h" &>/dev/null && echo "$h"; done
}

for _s in "${STEPS[@]}"; do declare "_do_${_s}=true"; done

# Which helper to install, and to use for every package list afterwards.
# yay by default: it builds faster and needs less setup than paru on a bare
# system, which is the situation where this actually gets installed.
_aur_helper="yay"         # yay | paru | both

# Which login screen. SDDM is the default; greetd + sysc-greet (Hyprland) is
# the lighter alternative. See cmd/lib/greeter.sh.
_greeter="sddm"

_flag_noninteractive=false

_set_steps() {   # _set_steps <on|off> <comma-separated names>
    local state="$1" list="${2//,/ }" s
    for s in $list; do
        if [[ " ${STEPS[*]} " != *" $s "* ]]; then
            error "Unknown step: $s"
            error "Valid: ${STEPS[*]}"
            exit 1
        fi
        declare -g "_do_${s}=$state"
    done
}

_only() {  # keep just the named steps
    local s
    for s in "${STEPS[@]}"; do declare -g "_do_${s}=false"; done
    _set_steps true "$1"
    _flag_noninteractive=true
}

# ------------------------------------------------------------------
# Parse flags
# ------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --all)       _flag_noninteractive=true ;;
        --hyprland)  ;;  # Hyprland es el único escritorio; se acepta por compatibilidad
        --greeter=*) _greeter="${1#*=}"
                     [[ "$_greeter" =~ ^(sddm|greetd)$ ]] || {
                         error "--greeter must be sddm or greetd"; exit 1; } ;;
        --aur-helper=*) _aur_helper="${1#*=}"
                     [[ "$_aur_helper" =~ ^(yay|paru|both)$ ]] || {
                         error "--aur-helper must be yay, paru or both"; exit 1; } ;;
        --only)      _only "$2"; shift ;;
        --only=*)    _only "${1#*=}" ;;
        --skip)      _set_steps false "$2"; _flag_noninteractive=true; shift ;;
        --skip=*)    _set_steps false "${1#*=}"; _flag_noninteractive=true ;;

        # Shorthands kept for the combinations used most often.
        --dotfiles)     _only dotfiles ;;
        --pkgs)         _only aur,desktop,apps ;;
        --desktop-only) _only desktop,dotfiles ;;

        -h|--help)
            cat <<EOF
Usage: setup post [options]

Everything except the initial Arch install, which is 'setup install' and only
runs once from the live ISO. Run it whole or a step at a time.

Steps:
$(for s in "${STEPS[@]}"; do printf '    %s\n' "$(_step_label "$s")"; done)

Options:
    --all               Run every step without prompting
    --only a,b,c        Run only these steps
    --skip a,b          Run everything except these
    --greeter=sddm      Graphical Qt login with the astronaut theme (default)
    --greeter=greetd    Console login: greetd + sysc-greet (Hyprland)
    --aur-helper=yay    Which helper to install and use (default; or paru, both)
    -h, --help          Show this help

Examples:
    setup post                     pick steps in a menu
    setup post --all               everything, no prompts
    setup post --only greeter      just the login screen
    setup post --skip apps,hwfix   everything but those two
    setup post --only dotfiles     just the ~/.config symlinks

To undo the dotfiles:
    setup dotfiles --unlink
EOF
            exit 0
            ;;
        *)
            # Without this a typo like --onyl would be ignored silently.
            error "Unknown option: $1"
            error "See: setup post --help"
            exit 1
            ;;
    esac
    shift
done

# ------------------------------------------------------------------
# Interactive selection
# ------------------------------------------------------------------
# whiptail gives real checkboxes on a bare TTY, which is where this runs after a
# fresh install. has_menu() falls back when it is missing or stdin is a pipe.
_have_helpers="$(_installed_helpers)"

if [[ "$_flag_noninteractive" == false ]] && has_menu; then
    # The AUR step only makes sense as a choice when a helper already exists.
    # With none installed nothing below step 2 can run, so it is forced on and
    # the only question is which one to install.
    if [[ -z "$_have_helpers" ]]; then
        _do_aur=true
        _aur_helper="$(menu_radiolist "AUR helper — required" \
"No AUR helper found. Steps 3 and below install through one, so this cannot be\n\
skipped. Which do you want?" \
            yay  "yay  — faster to build, less setup (recommended)" on \
            paru "paru — nicer output, written in Rust"             off \
            both "both — install the two of them"                   off)" \
            || { info "Cancelled."; exit 0; }
    else
        # One is already there, so installing is opt-in; the existing one is
        # what the package steps will use.
        _do_aur=false
        _aur_helper="$(echo "$_have_helpers" | head -1)"
        info "AUR helper found: $(echo "$_have_helpers" | tr '\n' ' ')— using $_aur_helper"
    fi

    _greeter="$(menu_radiolist "Login screen" \
"What you see when you boot. Only one can be enabled at a time." \
        sddm   "SDDM — graphical, themed (astronaut)"      on \
        greetd "greetd + sysc-greet — console, Hyprland"  off)" \
        || { info "Cancelled."; exit 0; }

    # Steps are listed in the order they must run. Each assumes the ones above
    # are done; unchecking one means "already handled some other way".
    _items=()
    for _s in "${STEPS[@]}"; do
        _v="_do_${_s}"
        _items+=("$_s" "${STEP_DESC[$_s]}" "$([[ ${!_v} == true ]] && echo on || echo off)")
    done
    _chosen="$(menu_checklist "Post-install — hyprland, $_greeter" \
"Space toggles · Tab to the buttons · Enter confirms\n\
Listed in the order they run; each assumes the ones above it." \
        "${_items[@]}")" || { info "Cancelled."; exit 0; }

    for _s in "${STEPS[@]}"; do declare "_do_${_s}=false"; done
    while read -r _s; do [[ -n "$_s" ]] && declare "_do_${_s}=true"; done <<<"$_chosen"

    # Unticking the AUR step with no helper installed would make every package
    # step below fail one by one. Put it back rather than let that happen.
    if [[ -z "$_have_helpers" && "$_do_aur" == false ]]; then
        for _s in desktop apps greeter; do
            _v="_do_${_s}"; [[ ${!_v} == true ]] || continue
            warn "Re-enabling the AUR step: '$_s' installs packages and no helper exists yet."
            _do_aur=true
            break
        done
    fi

elif [[ "$_flag_noninteractive" == false && -t 0 ]]; then
    # whiptail missing: confirm the defaults rather than silently doing everything.
    echo
    info "whiptail not available — running with defaults:"
    for _s in "${STEPS[@]}"; do
        _v="_do_${_s}"
        printf "    [%s] %s\n" "$([[ ${!_v} == true ]] && echo x || echo ' ')" "$(_step_label "$_s")"
    done
    echo
    read -rp "  Continue? [y/N] " _yn
    [[ "$_yn" =~ ^[Yy]$ ]] || { info "Cancelled."; exit 0; }
fi

echo
info "Login screen: $_greeter"
info "Steps: $(for s in "${STEPS[@]}"; do v="_do_$s"; [[ ${!v} == true ]] && printf '%s ' "$s"; done)"
echo

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
# 2. AUR helper (yay, paru, or both)
# ------------------------------------------------------------------
# Bootstrapped from source with makepkg, because installing an AUR package is
# the one thing you cannot do with an AUR helper you do not have yet.
if [[ $_do_aur == true ]]; then
    step "AUR helper ($_aur_helper)"

    case "$_aur_helper" in
        both) _want_helpers=(yay paru) ;;
        *)    _want_helpers=("$_aur_helper") ;;
    esac

    for _h in "${_want_helpers[@]}"; do
        if command -v "$_h" &>/dev/null; then
            info "$_h is already installed, skipping"
            continue
        fi
        AUR_TMP=$(mktemp -d)
        trap 'rm -rf "$AUR_TMP"; sudo_stop_keepalive' EXIT INT TERM
        git clone "https://aur.archlinux.org/${_h}.git" "$AUR_TMP"
        (cd "$AUR_TMP" && makepkg -si --noconfirm)
        rm -rf "$AUR_TMP"
        success "$_h installed"
    done
fi

# ------------------------------------------------------------------
# helper: which AUR helper the package steps below should use
# ------------------------------------------------------------------
# Honours the choice made above when it names one, so asking for paru does not
# silently install through yay just because yay sorts first. With 'both', or
# when the step was skipped, fall back to whatever is on the system.
_find_aur_helper() {
    if [[ "$_aur_helper" != "both" ]] && command -v "$_aur_helper" &>/dev/null; then
        echo "$_aur_helper"; return
    fi
    for h in paru yay; do
        command -v "$h" &>/dev/null && { echo "$h"; return; }
    done
}

# ------------------------------------------------------------------
# 3. Desktop packages — Hyprland + Quickshell
# ------------------------------------------------------------------
if [[ $_do_desktop == true ]]; then
    step "Desktop packages (hyprland)"

    _pkg_files=(deps-hyprland.conf deps-quickshell.conf)

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
# 3b. Pinned quickshell + Python venv — things the plain package lists cannot
#     express.
# ------------------------------------------------------------------
if [[ $_do_desktop == true ]]; then
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
# 5. Login screen
# ------------------------------------------------------------------
if [[ $_do_greeter == true ]]; then
    step "Login screen ($_greeter)"

    # All of it lives in cmd/lib/greeter.sh, so the same code serves
    # 'setup greeter apply' later — after a monitor layout change, say. It
    # installs the packages, writes the config, adds the GRUB console entry as
    # a way back in, and switches display-manager.service.
    bash "$REPO_ROOT/cmd/lib/greeter.sh" "$_greeter"

    # gnome-keyring PAM integration (auto-unlock on login).
    # Each of these is a separate PAM stack: /etc/pam.d/login covers TTY logins,
    # and the display manager has its own. Both greeters are listed so switching
    # between them does not silently lose the auto-unlock.
    for _pam in /etc/pam.d/login /etc/pam.d/sddm /etc/pam.d/greetd; do
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

    success "Login screen configured"
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
echo "  Log out and back in (or reboot) to start the session."

# The login screen's output config is generated from ~/.config/hypr/monitors.lua,
# which does not exist yet on a fresh machine: it is written once the display
# layout is set in the session, and it is in local.ignore so it never ships with
# the repo. Until then weston enables every output and the greeter can appear on
# a screen that is switched off.
if [[ $_do_greeter == true && ! -f "$HOME/.config/hypr/monitors.lua" ]]; then
    echo ""
    warn "Multi-monitor machines: set up your displays in the session first,"
    warn "then re-run 'setup greeter apply' so the login screen lands on the right one."
fi
