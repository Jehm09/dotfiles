#!/usr/bin/env bash
# Login screen.
#
# Two options, mutually exclusive — only one display manager may be enabled,
# since /etc/systemd/system/display-manager.service is a single symlink:
#
#   sddm     Graphical Qt login with the astronaut theme. Themed, picks between
#            the Hyprland and Plasma sessions, but its Wayland greeter runs
#            under weston and is fussy about GPUs and multi-head layouts.
#   greetd   Console greeter (sysc-greet, Cagebreak variant). Lighter, no
#            compositor quirks, no theming.
#
# SDDM's greeter has three failure modes that all look like "it does not start",
# and all three are handled here rather than left to be rediscovered:
#
#   1. IT DRAWS ON EVERY SCREEN, INCLUDING ONES THAT ARE OFF. SDDM instantiates
#      the theme on every QScreen the compositor exposes — core behaviour, not
#      the theme — so on a multi-head box the login form can land on a monitor
#      you are not looking at, while the journal reports "Greeter session started
#      successfully". Displays are left alone by default so this repo installs
#      anywhere; GREETER_OUTPUT pins it to one when you want that.
#
#   2. seatd BREAKS BOTH GREETERS. libseat prefers seatd when its socket exists
#      and does not fall back to logind when the socket is there but unreadable.
#      /run/seatd.sock is root:seat and greetd's greeter runs as `greeter`, which
#      is not in that group, so enabling seatd gives "Permission denied" and the
#      greeter dies on EGL. With SDDM it gives "Device already taken" and input
#      stops working. logind handles seats on its own; seatd stays off for both.
#
#   3. THE POINTER IS INVISIBLE UNDER WESTON. Nothing draws it: weston does not
#      implement wp_cursor_shape_manager_v1 (which Qt 6 asks for), neither of its
#      shells sets a default pointer image, and SDDM never exports XCURSOR_THEME
#      — it only has its own CursorTheme= key, which the compositor never sees.
#      Dropping weston to legacy KMS with WESTON_DISABLE_ATOMIC does not help;
#      that only fixes the NVIDIA cursor plane, and the problem is upstream of it.
#      Fixed by using kwin_wayland as the greeter compositor instead, which does
#      implement cursor-shape-v1. See GREETER_COMPOSITOR below.
#
# And one thing that makes it genuinely crash: never set
# GreeterEnvironment=QT_WAYLAND_SHELL_INTEGRATION=layer-shell. weston's
# kiosk-shell does not implement wlr-layer-shell, Qt then fails to load its
# platform plugin, and the greeter aborts on every boot.
#
# Usage:
#   setup greeter sddm      Install, configure and enable SDDM
#   setup greeter greetd    Install, configure and enable greetd + sysc-greet
#   setup greeter apply     Re-apply the config of whichever is active
#   setup greeter test      Preview the SDDM theme in a window, changing nothing
#   setup greeter status    Which one is active, and what would break

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$DOTFILES_DIR/cmd/lib/utils.sh"

THEME_DIR="/usr/share/sddm/themes/sddm-astronaut-theme"
THEME_VARIANT="hyprland_kath"
CONF_D="/etc/sddm.conf.d"
WESTON_INI="/etc/sddm/weston.ini"
GREETD_CONF="/etc/greetd/config.toml"
CAGEBREAK_CONF="/etc/greetd/cagebreak-greeter-config"

# SDDM draws no pointer at all unless told which theme to use — there is no
# fallback, it is simply invisible. Matches what Hyprland sets in
# hyprland/execs.lua and what KDE uses in kcminputrc, so the pointer does not
# change shape between the login screen and the session.
CURSOR_THEME="Bibata-Modern-Classic"
CURSOR_SIZE="24"

# Which compositor draws the SDDM greeter.
#
#   kwin     kwin_wayland. Implements wp_cursor_shape_manager_v1, which is what
#            Qt 6 asks for, so the pointer is actually drawn. Picks its own
#            outputs, so weston.ini does not apply.
#   weston   SDDM's default. Honours weston.ini — which is the only way to pin
#            the greeter to one monitor — but has NO cursor at all: it does not
#            implement cursor-shape-v1, and neither of its shells sets a default
#            pointer image, so nothing ever draws one.
#
# kwin by default: a login screen you cannot point at is worse than one that
# might come up on the wrong monitor. Set GREETER_COMPOSITOR=weston to swap.
GREETER_COMPOSITOR="${GREETER_COMPOSITOR:-kwin}"

# Restrict the greeter to one output, e.g. GREETER_OUTPUT=DP-5.
#
# EMPTY BY DEFAULT ON PURPOSE. SDDM renders the theme on every connected screen
# — that is SDDM core behaviour, not the theme — and leaving the displays alone
# is what makes this repo installable on any machine. Only set it when you
# actually want the login pinned to one monitor, and remember it is a property
# of that machine, not of the config.
GREETER_OUTPUT="${GREETER_OUTPUT:-}"

# What local.conf had before this run. Lets 'apply' tell "never pinned" (leave
# the machine alone) apart from "explicitly unpinned" (undo what we set), so a
# fresh install never deletes an output config it did not write.
_PREV_OUTPUT="$GREETER_OUTPUT"

_active_dm() {
    basename "$(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null || echo none)" .service
}

_install_pkgs() {
    local conf="$DOTFILES_DIR/packages/$1" helper
    helper=""
    for h in paru yay; do command -v "$h" &>/dev/null && { helper="$h"; break; }; done
    [[ -n "$helper" ]] || { error "No AUR helper found (paru/yay)"; exit 1; }

    local pkgs=()
    mapfile -t pkgs < <(parse_packages "$conf")
    info "Installing ${#pkgs[@]} packages from $(basename "$conf")..."
    "$helper" -S --needed --noconfirm "${pkgs[@]}"
}

# Refuse to switch display managers without a way back to a console. A greeter
# that fails to start leaves no TTY to fix it from, and the only recourse is
# editing the kernel line from GRUB by hand on every boot.
_require_rescue() {
    [[ -f /boot/grub/custom.cfg ]] && return 0
    warn "There is no GRUB console entry — if the greeter fails you are locked out."
    info "Adding one now..."
    bash "$DOTFILES_DIR/cmd/lib/grub.sh" rescue
}

# ------------------------------------------------------------------
# SDDM
# ------------------------------------------------------------------

# Pin the greeter to a single output. Opt-in — see GREETER_OUTPUT.
#
# There is no setting in SDDM for this: it instantiates the theme on every
# QScreen it is given, so the only lever is which outputs the compositor exposes.
# Each compositor needs a different file, and neither is something SDDM knows
# about.
# Put the greeter on one output, by raising that output's priority.
#
# Only `prio`. Not `disable`, and not `pos/res/rate`:
#   output <other> disable  -> the greeter exits with
#                              "EGL: Failed to initialize EGL" and greetd loops.
#                              Reproduced on this machine; cause not understood.
#   output <name> pos ... res ... rate ...  -> same failure.
# `prio <n>` leaves every output enabled and only reorders them, and the greeter
# lands on the first. The others stay lit — that is the trade-off for a greeter
# that actually starts.
_cagebreak_restrict() {
    local keep="$1"
    local block

    block="# >>> setup greeter: outputs"$'\n'
    block+="output $keep prio 10"$'\n'
    block+="# <<< setup greeter: outputs"$'\n'

    sudo awk -v block="$block" '
        /^# >>> setup greeter: outputs/ { skip = 1 }
        skip && /^# <<< setup greeter: outputs/ { skip = 0; next }
        skip { next }
        !done && /^exec / { printf "%s", block; done = 1 }
        { print }
        END { if (!done) printf "%s", block }
    ' "$CAGEBREAK_CONF" | sudo tee "$CAGEBREAK_CONF.tmp" >/dev/null
    sudo mv "$CAGEBREAK_CONF.tmp" "$CAGEBREAK_CONF"
    success "cagebreak: greeter on $keep (other outputs stay enabled)"
}

_restrict_output() {
    local keep="$1"
    local connected=()
    mapfile -t connected < <(_connected_outputs)

    if [[ ${#connected[@]} -eq 0 ]]; then
        warn "Could not read the connected outputs from /sys/class/drm — skipping."
        return 0
    fi
    if [[ " ${connected[*]} " != *" $keep "* ]]; then
        error "Output '$keep' is not connected. Connected: ${connected[*]}"
        exit 1
    fi

    if [[ "$(_active_dm)" == greetd ]]; then
        _cagebreak_restrict "$keep"
        return 0
    fi

    case "$GREETER_COMPOSITOR" in
    weston)
        sudo mkdir -p "$(dirname "$WESTON_INI")"
        {
            echo "# Generated by 'setup greeter apply' — GREETER_OUTPUT=$keep"
            echo
            local o
            for o in "${connected[@]}"; do
                echo "[output]"
                echo "name=$o"
                [[ "$o" == "$keep" ]] || echo "mode=off"
                echo
            done
        } | sudo tee "$WESTON_INI" >/dev/null
        success "weston.ini: only $keep enabled"
        ;;
    kwin)
        # kwin has no command-line switch for this; it reads its output state
        # from kwinoutputconfig.json under the greeter's HOME. Only the
        # connectorName/enabled pair is needed to disable one.
        #
        # Best effort: the surrounding structure is versioned and kwin rewrites
        # the file when it does not understand it. A rejected file means every
        # output stays on — the behaviour you already have — not a broken login.
        local kwin_cfg=/var/lib/sddm/.local/share/kwinoutputconfig.json
        sudo mkdir -p "$(dirname "$kwin_cfg")"
        {
            echo '{'
            echo '  "outputs": ['
            local o first=1
            for o in "${connected[@]}"; do
                [[ $first -eq 1 ]] || echo '    ,'
                first=0
                printf '    { "connectorName": "%s", "enabled": %s }\n' \
                    "$o" "$([[ "$o" == "$keep" ]] && echo true || echo false)"
            done
            echo '  ]'
            echo '}'
        } | sudo tee "$kwin_cfg" >/dev/null
        sudo chown -R sddm:sddm /var/lib/sddm/.local 2>/dev/null || true
        success "kwinoutputconfig.json: only $keep enabled"
        warn "kwin's config format is versioned; if it ignores this, every screen"
        warn "stays on. Use GREETER_COMPOSITOR=weston for a guaranteed pin (no cursor)."
        ;;
    esac
}

# Connector names as the kernel reports them: DP-5, HDMI-A-2, eDP-1...
# Same names weston and kwin use, and the same ones in Hyprland's monitors.lua.
_connected_outputs() {
    local card status name
    for status in /sys/class/drm/card*-*/status; do
        [[ -r "$status" ]] || continue
        [[ "$(cat "$status")" == connected ]] || continue
        card="${status%/status}"
        name="${card##*/}"
        echo "${name#card*-}"
    done
}

_sddm_configure() {
    [[ -d "$THEME_DIR" ]] || { error "Theme not installed: $THEME_DIR"; exit 1; }

    step "Theme variant"
    sudo sed -i "s|^ConfigFile=.*|ConfigFile=Themes/${THEME_VARIANT}.conf|" \
        "$THEME_DIR/metadata.desktop"

    # ScreenWidth/ScreenHeight are deliberately NOT set.
    #
    # Main.qml does `height: config.ScreenHeight || Screen.height`, so setting
    # them pins the theme to one resolution on EVERY connected screen — which
    # renders it at the primary's size on a secondary monitor of a different
    # size. Left empty, the theme reads each Screen and adapts, which is both
    # correct here and what makes this installable on any machine.
    success "Variant ${THEME_VARIANT} (resolution left to the theme)"

    # Both settings are remembered in local.conf, so a later plain
    # 'setup greeter apply' does not quietly undo them. Passing the variable
    # again overrides and re-saves; GREETER_OUTPUT= (empty) clears the pin.
    local_conf_set GREETER_COMPOSITOR "$GREETER_COMPOSITOR"

    # Output selection — opt-in only, see GREETER_OUTPUT.
    if [[ -n "$GREETER_OUTPUT" ]]; then
        step "Restricting the greeter to $GREETER_OUTPUT"
        _restrict_output "$GREETER_OUTPUT"
        local_conf_set GREETER_OUTPUT "$GREETER_OUTPUT"
        info "Saved to $(basename "$DOTFILES_LOCAL_CONF") — future runs keep this."
    elif [[ -n "${_PREV_OUTPUT:-}" ]]; then
        # Was pinned, now explicitly empty: that is a request to unpin, so drop
        # the compositor's output config too.
        step "Unpinning the greeter (was $_PREV_OUTPUT)"
        sudo rm -f "$WESTON_INI" /var/lib/sddm/.local/share/kwinoutputconfig.json 2>/dev/null || true
        local_conf_set GREETER_OUTPUT ""
        success "The greeter will show on every screen again."
    else
        # Never pinned. Touch nothing: a fresh install must leave the displays
        # exactly as they are, and any output config here would be someone
        # else's, not ours to delete.
        info "Displays left untouched — the greeter shows on every screen."
        info "Pin it with: GREETER_OUTPUT=DP-5 setup greeter apply"
    fi

    step "SDDM configuration"
    # Drop-ins rather than /etc/sddm.conf: that file is a .pacnew magnet, and
    # drop-ins keep our settings separate from the shipped defaults.
    sudo tee "$CONF_D/10-theme.conf" >/dev/null <<CONF
# Managed by 'setup greeter apply'.
[Theme]
Current=sddm-astronaut-theme
CursorTheme=$CURSOR_THEME
CursorSize=$CURSOR_SIZE
CONF
    sudo tee "$CONF_D/20-virtualkbd.conf" >/dev/null <<'CONF'
# Managed by 'setup greeter apply'.
[General]
InputMethod=qtvirtualkeyboard
CONF
    # XCURSOR_* is passed explicitly because SDDM's own CursorTheme= never
    # reaches the compositor — there is no XCURSOR string in any sddm binary.
    local compositor_cmd
    case "$GREETER_COMPOSITOR" in
    kwin)
        # --no-lockscreen and --no-global-shortcuts because this is a login
        # screen, not a session: nothing to lock, and no user shortcuts to honour.
        compositor_cmd="env XCURSOR_THEME=$CURSOR_THEME XCURSOR_SIZE=$CURSOR_SIZE kwin_wayland --no-lockscreen --no-global-shortcuts --locale1"
        ;;
    weston)
        # WESTON_DISABLE_ATOMIC drops weston to legacy KMS, which is the usual
        # workaround for the NVIDIA cursor plane. It does not help here — weston
        # draws no cursor at all — but it costs nothing and matters on other GPUs.
        compositor_cmd="env WESTON_DISABLE_ATOMIC=1 XCURSOR_THEME=$CURSOR_THEME XCURSOR_SIZE=$CURSOR_SIZE weston --shell=kiosk --config=$WESTON_INI"
        ;;
    *)  error "GREETER_COMPOSITOR must be kwin or weston"; exit 1 ;;
    esac

    sudo tee "$CONF_D/30-wayland.conf" >/dev/null <<CONF
# Managed by 'setup greeter apply'. Compositor: $GREETER_COMPOSITOR
[General]
DisplayServer=wayland
GreeterEnvironment=XCURSOR_THEME=$CURSOR_THEME,XCURSOR_SIZE=$CURSOR_SIZE

[Wayland]
CompositorCommand=$compositor_cmd
CONF
    success "Wrote $CONF_D/{10-theme,20-virtualkbd,30-wayland}.conf (compositor: $GREETER_COMPOSITOR)"
    [[ "$GREETER_COMPOSITOR" == kwin ]] && \
        info "kwin picks its own outputs — weston.ini does not apply to it."

    step "seatd"
    if systemctl is-enabled seatd &>/dev/null; then
        info "Disabling seatd — it belongs to greetd and blocks weston's input devices"
        sudo systemctl disable --now seatd
    fi
    success "seatd disabled (correct for SDDM)"
}

cmd_sddm() {
    prevent_root
    _install_pkgs deps-greeter-sddm.conf
    _sddm_configure
    _require_rescue

    step "Switching display manager"
    systemctl is-enabled greetd &>/dev/null && sudo systemctl disable greetd
    sudo systemctl enable sddm
    success "SDDM enabled. greetd stays installed; 'setup greeter greetd' switches back."
    info "Preview without logging out:  setup greeter test"
}

# ------------------------------------------------------------------
# greetd + sysc-greet (Cagebreak)
# ------------------------------------------------------------------
# Unlock the login keyring with the login password.
#
# Appends after the LAST auth/session line rather than after pam_unix: greetd's
# stack has no pam_unix of its own, it does `include system-local-login`, so
# anchoring on pam_unix silently does nothing. Without this you get a password
# prompt from gnome-keyring on every login.
_pam_keyring() {
    local f="$1"
    [[ -f "$f" ]] || return 0
    grep -q pam_gnome_keyring "$f" && return 0

    sudo awk '
        { lines[NR] = $0 }
        /^auth/    { last_auth = NR }
        /^session/ { last_session = NR }
        END {
            for (i = 1; i <= NR; i++) {
                print lines[i]
                if (i == last_auth)    print "auth       optional     pam_gnome_keyring.so"
                if (i == last_session) print "session    optional     pam_gnome_keyring.so auto_start"
            }
        }
    ' "$f" | sudo tee "$f.tmp" >/dev/null
    sudo mv "$f.tmp" "$f"
    success "gnome-keyring unlock added to $f"
}

_greetd_configure() {
    step "greetd configuration"
    sudo mkdir -p "$(dirname "$GREETD_CONF")"

    if [[ -n "$GREETER_OUTPUT" && -f "$CAGEBREAK_CONF" ]]; then
        _cagebreak_restrict "$GREETER_OUTPUT"
    fi
    # Matches what the upstream installer writes
    # (https://github.com/Nomadcxx/sysc-greet). greetd launches cagebreak; the
    # cagebreak config exec's the greeter. -e enables the IPC socket used to quit
    # cagebreak after login, which is why socat is a dependency.
    sudo tee "$GREETD_CONF" >/dev/null <<'TOML'
# Managed by 'setup greeter apply'.
[terminal]
vt = 1

[default_session]
command = "cagebreak -e -c /etc/greetd/cagebreak-greeter-config"
user = "greeter"

[initial_session]
command = "cagebreak -e -c /etc/greetd/cagebreak-greeter-config"
user = "greeter"
TOML
    success "Wrote $GREETD_CONF"

    step "Keyring"
    _pam_keyring /etc/pam.d/greetd

    # seatd is deliberately not touched. The upstream installer does not use it
    # and logind handles seats on its own. Enabling it breaks the greeter:
    # /run/seatd.sock is root:seat, greetd's greeter runs as `greeter` which is
    # not in that group, and libseat does not fall back to logind when the socket
    # exists but is unreadable — it fails with "Permission denied" and cagebreak
    # dies on EGL.
}

cmd_greetd() {
    prevent_root
    _install_pkgs deps-greeter-greetd.conf
    _greetd_configure
    _require_rescue

    step "Switching display manager"
    systemctl is-enabled sddm &>/dev/null && sudo systemctl disable sddm
    sudo systemctl enable greetd
    success "greetd enabled. 'setup greeter sddm' switches back."
}

# ------------------------------------------------------------------
# Shared
# ------------------------------------------------------------------
cmd_apply() {
    prevent_root
    case "$(_active_dm)" in
        sddm)   _sddm_configure   ;;
        greetd) _greetd_configure ;;
        *)      error "No display manager is enabled. Run 'setup greeter sddm' or 'setup greeter greetd'."
                exit 1 ;;
    esac
}

cmd_test() {
    [[ -d "$THEME_DIR" ]] || { error "SDDM theme not installed: $THEME_DIR"; exit 1; }
    info "Rendering the SDDM greeter. It cannot authenticate — this only draws the theme."
    info "Close it with Super+Q."
    sddm-greeter-qt6 --test-mode --theme "$THEME_DIR"
}

cmd_status() {
    local dm
    dm="$(_active_dm)"
    echo
    echo -e "  ${_CLR_BOLD}Active${_CLR_RST}   $dm"
    echo

    if [[ ! -f /boot/grub/custom.cfg ]]; then
        warn "No GRUB console entry — a broken greeter would lock you out."
        warn "Run 'setup grub rescue'."
    else
        success "GRUB console entry present"
    fi

    case "$dm" in
    sddm)
        echo -e "  ${_CLR_BOLD}Theme${_CLR_RST}    $(grep -s '^ConfigFile=' "$THEME_DIR/metadata.desktop" | cut -d= -f2 || echo 'not installed')"
        local comp
        comp="$(grep -s '^CompositorCommand=' "$CONF_D/30-wayland.conf" | grep -oE 'kwin_wayland|weston' | head -1)"
        echo -e "  ${_CLR_BOLD}Compositor${_CLR_RST}  ${comp:-unknown}"
        if [[ "$comp" == weston ]]; then
            warn "weston draws no cursor: no cursor-shape-v1, and its shells set no"
            warn "default pointer image. Use kwin unless you need guaranteed output pinning."
        fi

        echo -e "  ${_CLR_BOLD}Connected${_CLR_RST}   $(_connected_outputs | tr '\n' ' ')"
        [[ -f "$DOTFILES_LOCAL_CONF" ]] && \
            echo -e "  ${_CLR_BOLD}local.conf${_CLR_RST}  $(grep -c '^GREETER' "$DOTFILES_LOCAL_CONF" 2>/dev/null || echo 0) saved setting(s)"
        if [[ -f "$WESTON_INI" ]] || [[ -f /var/lib/sddm/.local/share/kwinoutputconfig.json ]]; then
            success "Greeter pinned to one output (GREETER_OUTPUT was used)"
        else
            info "Greeter shows on every screen — the portable default."
            info "Pin it with: GREETER_OUTPUT=DP-5 setup greeter apply"
        fi
        systemctl is-enabled seatd &>/dev/null \
            && warn "seatd is enabled — it will fight logind for the input devices." \
            || success "seatd disabled (correct for SDDM)"
        if grep -rqs '^CursorTheme=' "$CONF_D"; then
            local ct
            ct="$(grep -rhs '^CursorTheme=' "$CONF_D" | head -1 | cut -d= -f2)"
            [[ -d "/usr/share/icons/$ct" ]] \
                && success "Cursor theme: $ct" \
                || warn "Cursor theme '$ct' is not in /usr/share/icons — no pointer will be drawn."
        else
            warn "No CursorTheme set — SDDM draws no pointer at all without one."
        fi
        grep -rqs 'QT_WAYLAND_SHELL_INTEGRATION' "$CONF_D" \
            && error "QT_WAYLAND_SHELL_INTEGRATION is set in $CONF_D — the greeter will crash."
        ;;
    greetd)
        [[ -f "$GREETD_CONF" ]] && {
            success "greetd session:"
            grep -E '^command' "$GREETD_CONF" | sed 's/^/      /'
        }
        systemctl is-enabled seatd &>/dev/null \
            && error "seatd is enabled — the greeter cannot read its socket and will fail on EGL. Disable it." \
            || success "seatd disabled (logind handles seats)"
        ;;
    *)
        warn "No display manager enabled."
        ;;
    esac
    echo
}

# Pre-flight: everything that has ever broken this greeter, checked without
# changing a thing. Run it before switching display manager.
cmd_check() {
    local fail=0
    echo

    step "greetd config"
    local cmd bin
    cmd="$(grep -m1 '^command' "$GREETD_CONF" 2>/dev/null | cut -d'"' -f2)"
    bin="${cmd%% *}"
    if [[ -z "$cmd" ]]; then
        error "No command in $GREETD_CONF"; fail=1
    elif command -v "$bin" &>/dev/null || [[ -x "$bin" ]]; then
        success "command: $cmd"
    else
        error "command names '$bin', which does not exist"; fail=1
    fi

    step "Binaries the greeter session runs"
    local b
    for b in cagebreak kitty socat gslapper /usr/local/bin/sysc-greet; do
        if command -v "$b" &>/dev/null || [[ -x "$b" ]]; then
            success "$(basename "$b")"
        else
            error "$(basename "$b") missing"; fail=1
        fi
    done

    step "Cagebreak config parses"
    if [[ -f "$CAGEBREAK_CONF" ]]; then
        if timeout 5 cagebreak -c "$CAGEBREAK_CONF" -s &>/dev/null; then
            success "$CAGEBREAK_CONF accepted"
        else
            error "cagebreak rejects $CAGEBREAK_CONF"; fail=1
        fi
    fi

    step "Seat access"
    # The greeter runs as `greeter`. libseat prefers seatd when its socket exists
    # and will NOT fall back to logind if it cannot read it.
    if systemctl is-enabled seatd &>/dev/null; then
        if id -nG greeter 2>/dev/null | grep -qw seat; then
            success "seatd enabled and greeter is in the seat group"
        else
            error "seatd is enabled but greeter is not in the seat group"
            error "  the greeter will fail: Permission denied on /run/seatd.sock"
            error "  fix: sudo systemctl disable --now seatd"
            fail=1
        fi
    else
        success "seatd disabled (logind handles seats)"
    fi

    step "Outputs"
    local o connected
    connected="$(_connected_outputs | tr '\n' ' ')"
    echo "      connected: $connected"
    for o in $(grep -oP '^output \K[A-Za-z0-9-]+' "$CAGEBREAK_CONF" 2>/dev/null); do
        if [[ " $connected " == *" $o "* ]]; then
            success "$o is connected"
        else
            warn "$o is in the config but not connected"
        fi
    done

    step "Keyring"
    grep -q pam_gnome_keyring /etc/pam.d/greetd 2>/dev/null \
        && success "pam_gnome_keyring present in /etc/pam.d/greetd" \
        || warn "no pam_gnome_keyring — you will be asked for the keyring password"

    step "Way back in"
    [[ -f /boot/grub/custom.cfg ]] \
        && success "GRUB console entry present" \
        || { error "no GRUB console entry — run 'setup grub rescue' first"; fail=1; }

    echo
    if [[ $fail -eq 0 ]]; then
        success "All checks passed. Safe to: sudo systemctl disable sddm && sudo systemctl enable --now greetd"
    else
        error "Fix the errors above before switching."
        return 1
    fi
}

_usage() {
    cat <<EOF

Usage: setup greeter <subcommand>

    sddm      Install, configure and enable SDDM + the astronaut theme
    greetd    Install, configure and enable greetd + sysc-greet (Cagebreak)
    apply     Re-apply the config of whichever is active
              (run after changing the monitor layout)
    test      Preview the SDDM theme in a window, changing nothing
    check     Validate the greetd setup without changing anything
    status    Which one is active, and what would break

Only one may be enabled: display-manager.service is a single symlink. Both
switches add a GRUB console entry first, so a greeter that fails to start
cannot lock you out.

EOF
}

case "${1:-}" in
    sddm)   shift; cmd_sddm   "$@" ;;
    greetd) shift; cmd_greetd "$@" ;;
    apply)  shift; cmd_apply  "$@" ;;
    test)   shift; cmd_test   "$@" ;;
    check)  shift; cmd_check  "$@" ;;
    status) shift; cmd_status "$@" ;;
    -h|--help|help|"") _usage ;;
    *) error "Unknown subcommand: $1"; _usage; exit 1 ;;
esac
