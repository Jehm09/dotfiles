#!/usr/bin/env bash
# Full desktop setup - runs inside arch-chroot as root.
#
# Installs everything needed for a working graphical session:
#   1. Desktop packages (pacman) from packages/desktop.txt
#   2. Personal apps (pacman) from packages/apps.txt
#   3. Configures greetd, seatd, NVIDIA Wayland env vars
#   4. Installs yay AUR helper as the regular user
#   5. AUR packages from packages/aur.txt
#   6. Post-user setup: fish as default shell, gnome-keyring, asdf, etc.
#   7. Symlinks dots/.config into the user's ~/.config

set -Eeuo pipefail

# Load hostname / username / password written by install.sh
source /root/setup/install.conf

PACKAGES_DIR="/root/packages"
DOTFILES_SRC="/root/dotfiles_src"
DOTFILES_DIR="/home/$USERNAME/dotfiles"

[[ -d "$PACKAGES_DIR" ]] || {
    echo "ERROR: Package directory not found: $PACKAGES_DIR"
    exit 1
}

# Move the dotfiles into the user's home so symlink.sh can run as that user
if [[ -d "$DOTFILES_SRC" && ! -d "$DOTFILES_DIR" ]]; then
    echo "Installing dotfiles to $DOTFILES_DIR..."
    cp -r "$DOTFILES_SRC" "$DOTFILES_DIR"
    chown -R "$USERNAME:$USERNAME" "$DOTFILES_DIR"
fi

# Parse a package file: strip comments and blank lines, one name per line
parse_packages() {
    grep -v '^\s*#' "$1" \
        | grep -v '^\s*$' \
        | awk '{print $1}' \
        | grep -v '^$'
}

# Run a command as the regular user (login shell so $HOME, $PATH are correct)
run_as_user() {
    su - "$USERNAME" -c "$*"
}

# ------------------------------------------------------------------
# 1. Install desktop packages
# ------------------------------------------------------------------
echo "Installing desktop packages..."
mapfile -t desktop_pkgs < <(parse_packages "$PACKAGES_DIR/desktop.txt")
pacman -S --needed --noconfirm "${desktop_pkgs[@]}"

# ------------------------------------------------------------------
# 2. Install personal apps (pacman)
# ------------------------------------------------------------------
echo "Installing personal apps..."
mapfile -t app_pkgs < <(parse_packages "$PACKAGES_DIR/apps.txt")
pacman -S --needed --noconfirm "${app_pkgs[@]}"

# ------------------------------------------------------------------
# 3. seatd - seat management for Hyprland
# ------------------------------------------------------------------
echo "Enabling seatd..."
systemctl enable seatd
usermod -aG seat "$USERNAME"

# ------------------------------------------------------------------
# 4. greetd login manager
# ------------------------------------------------------------------
# sysc-greet-hyprland is the graphical console greeter (Go + Bubble Tea).
# It is installed from AUR in step 6 below. greetd itself is already
# installed via desktop.txt.
echo "Configuring greetd..."
mkdir -p /etc/greetd

cat > /etc/greetd/config.toml <<'EOF'
[terminal]
vt = 1

[default_session]
# sysc-greet-hyprland: graphical console greeter for greetd, Hyprland variant.
# Installed from AUR (step 6). Source: https://github.com/b1rger/sysc-greet
command = "sysc-greet-hyprland"
user = "greeter"
EOF

systemctl enable greetd

# ------------------------------------------------------------------
# 5. NVIDIA Wayland environment variables
# ------------------------------------------------------------------
if lspci 2>/dev/null | grep -qi nvidia; then
    echo "Writing NVIDIA Wayland environment variables..."
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
# 6. Enable multilib (required for Steam)
# ------------------------------------------------------------------
echo "Enabling multilib repository..."
if ! grep -q '^\[multilib\]' /etc/pacman.conf; then
    sed -i '/^#\[multilib\]/{
        s/^#//
        n
        s/^#Include/Include/
    }' /etc/pacman.conf
    pacman -Sy --noconfirm
fi

# ------------------------------------------------------------------
# 7. Install yay as regular user
# ------------------------------------------------------------------
echo "Installing yay AUR helper as $USERNAME..."

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
# 8. Install AUR packages as regular user
# ------------------------------------------------------------------
echo "Installing AUR packages..."
mapfile -t aur_pkgs < <(parse_packages "$PACKAGES_DIR/aur.txt")
run_as_user "yay -S --needed --noconfirm ${aur_pkgs[*]}"

# ------------------------------------------------------------------
# 9. Post-user configuration
# ------------------------------------------------------------------

# Set fish as the default login shell
FISH_BIN="$(command -v fish)"
echo "Setting fish as default shell for $USERNAME..."
chsh -s "$FISH_BIN" "$USERNAME"

# Configure asdf-vm for fish
ASDF_CONF="/home/$USERNAME/.config/fish/conf.d/asdf.fish"
mkdir -p "$(dirname "$ASDF_CONF")"
echo 'source /opt/asdf-vm/asdf.fish' > "$ASDF_CONF"
chown "$USERNAME:$USERNAME" "$ASDF_CONF"

# nautilus-open-any-terminal: open kitty from right-click in Nautilus
run_as_user "gsettings set com.github.stunkymonkey.nautilus-open-any-terminal terminal kitty" || true

# gnome-keyring PAM integration (auto-unlock on login)
PAM_LOGIN="/etc/pam.d/login"
if [[ -f "$PAM_LOGIN" ]] && ! grep -q 'pam_gnome_keyring' "$PAM_LOGIN"; then
    echo "Configuring gnome-keyring PAM integration..."
    sed -i '/^auth.*pam_unix\.so/a auth       optional     pam_gnome_keyring.so' "$PAM_LOGIN"
    sed -i '/^session.*pam_unix\.so/a session    optional     pam_gnome_keyring.so auto_start' "$PAM_LOGIN"
fi

# Install Equicord + OpenAsar on Discord
if command -v Equilotl &>/dev/null && [[ -d /opt/discord ]]; then
    echo "Applying Equicord and OpenAsar to Discord..."
    Equilotl -install -location /opt/discord
    Equilotl -install-openasar -location /opt/discord
fi

# Install pacman hook for Equicord (auto-reinstall after Discord updates)
if [[ -d "$DOTFILES_DIR/hooks" ]]; then
    mkdir -p /etc/pacman.d/hooks
    install -Dm644 "$PACKAGES_DIR/hooks/equicord.hook" /etc/pacman.d/hooks/equicord.hook
fi

# ------------------------------------------------------------------
# 10. Symlink dots/.config into user's ~/.config
# ------------------------------------------------------------------
if [[ -f "$DOTFILES_DIR/scripts/symlink.sh" ]]; then
    echo "Linking dotfiles for $USERNAME..."
    run_as_user "bash $DOTFILES_DIR/scripts/symlink.sh"
fi

# ------------------------------------------------------------------
# 11. XDG desktop portals
# ------------------------------------------------------------------
systemctl --global enable xdg-desktop-portal || true

echo ""
echo "Desktop setup complete. Reboot to start the graphical session."
