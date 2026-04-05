#!/usr/bin/env bash
# Full desktop setup - runs inside arch-chroot as root.
#
# Installs everything needed for a working graphical session:
#   1. Desktop packages (Hyprland, greetd, Qt6, fonts, theming)
#   2. Personal apps
#   3. seatd + greetd configuration
#   4. NVIDIA Wayland environment variables (if NVIDIA GPU present)
#   5. Multilib repository (for Steam)
#   6. yay AUR helper (built as the regular user)
#   7. AUR packages (quickshell, hyprlock, sysc-greet-hyprland, etc.)
#   8. Post-user setup: fish shell, gnome-keyring, asdf, Equicord
#   9. Symlinks dots/.config into the user's ~/.config
#
# Called by cmd/arch/run.sh via arch-chroot.

set -Eeuo pipefail

DOTFILES="/root/dotfiles_src"
source "$DOTFILES/lib/utils.sh"
source /root/install.conf

PACKAGES_DIR="$DOTFILES/packages"
DOTFILES_DIR="/home/$USERNAME/dotfiles"

[[ -d "$PACKAGES_DIR" ]] || {
    error "Package directory not found: $PACKAGES_DIR"
    exit 1
}

# Move the dotfiles into the user's home so symlink.sh can run as that user.
if [[ ! -d "$DOTFILES_DIR" ]]; then
    info "Installing dotfiles to $DOTFILES_DIR..."
    cp -r "$DOTFILES" "$DOTFILES_DIR"
    chown -R "$USERNAME:$USERNAME" "$DOTFILES_DIR"
fi

# Run a command as the regular user (login shell so $HOME, $PATH are correct)
run_as_user() {
    su - "$USERNAME" -c "$*"
}

# ------------------------------------------------------------------
# 1. Desktop packages
# ------------------------------------------------------------------
step "Desktop packages"
mapfile -t _pkgs < <(parse_packages "$PACKAGES_DIR/desktop.conf")
pacman -S --needed --noconfirm "${_pkgs[@]}"

# ------------------------------------------------------------------
# 2. Personal apps
# ------------------------------------------------------------------
step "Personal apps"
mapfile -t _pkgs < <(parse_packages "$PACKAGES_DIR/apps.conf")
pacman -S --needed --noconfirm "${_pkgs[@]}"

# ------------------------------------------------------------------
# 3. seatd - seat management for Hyprland
# ------------------------------------------------------------------
step "seatd"
systemctl enable seatd
usermod -aG seat "$USERNAME"

# ------------------------------------------------------------------
# 4. greetd login manager
# ------------------------------------------------------------------
step "greetd"
mkdir -p /etc/greetd
cat > /etc/greetd/config.toml <<'EOF'
[terminal]
vt = 1

[default_session]
# sysc-greet-hyprland: graphical console greeter for greetd, Hyprland variant.
# Source: https://github.com/b1rger/sysc-greet
command = "sysc-greet-hyprland"
user = "greeter"
EOF
systemctl enable greetd

# ------------------------------------------------------------------
# 5. NVIDIA Wayland environment variables
# ------------------------------------------------------------------
if lspci 2>/dev/null | grep -qi nvidia; then
    step "NVIDIA Wayland environment"
    cat > /etc/environment <<'EOF'
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

# ------------------------------------------------------------------
# 6. Multilib repository (for Steam)
# ------------------------------------------------------------------
step "Multilib"
if ! grep -q '^\[multilib\]' /etc/pacman.conf; then
    sed -i '/^#\[multilib\]/{
        s/^#//
        n
        s/^#Include/Include/
    }' /etc/pacman.conf
    pacman -Sy --noconfirm
fi

# ------------------------------------------------------------------
# 7. yay AUR helper (built as regular user)
# ------------------------------------------------------------------
step "yay AUR helper"
if ! command -v yay &>/dev/null; then
    run_as_user "
        cd /tmp
        git clone https://aur.archlinux.org/yay.git yay-build
        cd yay-build
        makepkg -si --noconfirm
        cd /tmp && rm -rf yay-build
    "
fi

# ------------------------------------------------------------------
# 8. AUR packages
# ------------------------------------------------------------------
step "AUR packages"
mapfile -t _pkgs < <(parse_packages "$PACKAGES_DIR/aur.conf")
run_as_user "yay -S --needed --noconfirm ${_pkgs[*]}"

# ------------------------------------------------------------------
# 9. Post-user configuration
# ------------------------------------------------------------------
step "Post-user configuration"

# Set fish as the default login shell
_fish_bin="$(command -v fish)"
info "Setting fish as default shell for $USERNAME..."
chsh -s "$_fish_bin" "$USERNAME"

# Configure asdf-vm for fish
_asdf_conf="/home/$USERNAME/.config/fish/conf.d/asdf.fish"
mkdir -p "$(dirname "$_asdf_conf")"
echo 'source /opt/asdf-vm/asdf.fish' > "$_asdf_conf"
chown "$USERNAME:$USERNAME" "$_asdf_conf"

# nautilus-open-any-terminal: open kitty from right-click in Nautilus
run_as_user "gsettings set com.github.stunkymonkey.nautilus-open-any-terminal terminal kitty" || true

# gnome-keyring PAM integration (auto-unlock on login)
_pam_login="/etc/pam.d/login"
if [[ -f "$_pam_login" ]] && ! grep -q 'pam_gnome_keyring' "$_pam_login"; then
    info "Configuring gnome-keyring PAM integration..."
    sed -i '/^auth.*pam_unix\.so/a auth       optional     pam_gnome_keyring.so' "$_pam_login"
    sed -i '/^session.*pam_unix\.so/a session    optional     pam_gnome_keyring.so auto_start' "$_pam_login"
fi

# Discord + Equicord
if command -v Equilotl &>/dev/null && [[ -d /opt/discord ]]; then
    info "Applying Equicord and OpenAsar to Discord..."
    Equilotl -install -location /opt/discord
    Equilotl -install-openasar -location /opt/discord
fi

# pacman hooks (e.g. equicord.hook: reinstall after Discord updates)
mkdir -p /etc/pacman.d/hooks
for hook in "$PACKAGES_DIR/hooks/"*.hook; do
    [[ -f "$hook" ]] || continue
    install -Dm644 "$hook" "/etc/pacman.d/hooks/$(basename "$hook")"
done

# ------------------------------------------------------------------
# 10. Dotfiles symlinks
# ------------------------------------------------------------------
step "Dotfiles"
run_as_user "bash $DOTFILES_DIR/lib/symlink.sh"

# ------------------------------------------------------------------
# 11. XDG desktop portals
# ------------------------------------------------------------------
systemctl --global enable xdg-desktop-portal || true

echo ""
success "Desktop setup complete. Reboot to start the graphical session."
