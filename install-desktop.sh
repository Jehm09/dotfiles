#!/usr/bin/env bash
# Graphical desktop installer for an existing Arch Linux system.
# Run as your regular user (with sudo access) from the dotfiles root.
#
# Use this when you already have Arch Linux installed and want to set up:
#   - Hyprland + Wayland compositor
#   - Quickshell (QML shell: bar, launcher, notifications, OSD)
#   - greetd + sysc-greet-hyprland login manager
#   - All personal apps
#   - Dotfile symlinks (dots/.config -> ~/.config)
#
# For a fresh Arch Linux install from ISO, use install.sh instead.

set -Eeuo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGES_DIR="$DOTFILES_DIR/packages"

echo "Desktop installer"
echo "Dotfiles: $DOTFILES_DIR"
echo ""

# ------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------
parse_packages() {
    grep -v '^\s*#' "$1" \
        | grep -v '^\s*$' \
        | awk '{print $1}' \
        | grep -v '^$'
}

# ------------------------------------------------------------------
# 1. Enable multilib (required for Steam)
# ------------------------------------------------------------------
echo "==> Enabling multilib..."
bash "$DOTFILES_DIR/scripts/multilib.sh"

# ------------------------------------------------------------------
# 2. Install desktop packages (Hyprland, greetd, Qt/Wayland, Quickshell deps)
# ------------------------------------------------------------------
echo "==> Installing desktop packages..."
mapfile -t desktop_pkgs < <(parse_packages "$PACKAGES_DIR/desktop.txt")
sudo pacman -S --needed --noconfirm "${desktop_pkgs[@]}"

# ------------------------------------------------------------------
# 3. Install personal apps (pacman)
# ------------------------------------------------------------------
echo "==> Installing personal apps..."
mapfile -t app_pkgs < <(parse_packages "$PACKAGES_DIR/apps.txt")
sudo pacman -S --needed --noconfirm "${app_pkgs[@]}"

# ------------------------------------------------------------------
# 4. Install yay AUR helper
# ------------------------------------------------------------------
echo "==> Installing yay..."
bash "$DOTFILES_DIR/scripts/yay.sh"

# ------------------------------------------------------------------
# 5. Install AUR packages (quickshell-git, sysc-greet-hyprland, etc.)
# ------------------------------------------------------------------
echo "==> Installing AUR packages..."
mapfile -t aur_pkgs < <(parse_packages "$PACKAGES_DIR/aur.txt")
yay -S --needed --noconfirm "${aur_pkgs[@]}"

# ------------------------------------------------------------------
# 6. seatd - seat management for Hyprland
# ------------------------------------------------------------------
echo "==> Enabling seatd..."
sudo systemctl enable --now seatd
sudo usermod -aG seat "$USER"

# ------------------------------------------------------------------
# 7. greetd login manager
# ------------------------------------------------------------------
echo "==> Configuring greetd..."
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

# ------------------------------------------------------------------
# 8. NVIDIA Wayland environment variables (if NVIDIA GPU is present)
# ------------------------------------------------------------------
if lspci 2>/dev/null | grep -qi nvidia; then
    echo "==> Writing NVIDIA Wayland environment variables..."
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

# ------------------------------------------------------------------
# 9. Post-user setup
# ------------------------------------------------------------------

# Fish as default shell
FISH_BIN="$(command -v fish)"
if [[ "$SHELL" != "$FISH_BIN" ]]; then
    echo "==> Setting fish as default shell..."
    chsh -s "$FISH_BIN"
fi

# asdf-vm for fish
ASDF_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/fish/conf.d/asdf.fish"
if [[ ! -f "$ASDF_CONF" ]]; then
    echo "==> Configuring asdf-vm for fish..."
    mkdir -p "$(dirname "$ASDF_CONF")"
    echo 'source /opt/asdf-vm/asdf.fish' > "$ASDF_CONF"
fi

# nautilus-open-any-terminal -> kitty
if command -v gsettings &>/dev/null; then
    gsettings set com.github.stunkymonkey.nautilus-open-any-terminal terminal kitty || true
fi

# gnome-keyring PAM integration
PAM_LOGIN="/etc/pam.d/login"
if [[ -f "$PAM_LOGIN" ]] && ! grep -q 'pam_gnome_keyring' "$PAM_LOGIN"; then
    echo "==> Configuring gnome-keyring PAM integration..."
    sudo sed -i '/^auth.*pam_unix\.so/a auth       optional     pam_gnome_keyring.so' "$PAM_LOGIN"
    sudo sed -i '/^session.*pam_unix\.so/a session    optional     pam_gnome_keyring.so auto_start' "$PAM_LOGIN"
fi

# ------------------------------------------------------------------
# 10. Discord + Equicord
# ------------------------------------------------------------------
echo "==> Setting up Discord with Equicord..."
yay -S --needed --noconfirm discord equicord-installer-bin
if command -v Equilotl &>/dev/null; then
    sudo Equilotl -install -location /opt/discord
    sudo Equilotl -install-openasar -location /opt/discord
fi

# ------------------------------------------------------------------
# 11. pacman hooks
# ------------------------------------------------------------------
echo "==> Installing pacman hooks..."
sudo mkdir -p /etc/pacman.d/hooks
for hook in "$DOTFILES_DIR"/packages/hooks/*.hook; do
    [[ -f "$hook" ]] || continue
    sudo install -Dm644 "$hook" "/etc/pacman.d/hooks/$(basename "$hook")"
done

# ------------------------------------------------------------------
# 12. Symlink dots/.config -> ~/.config
# ------------------------------------------------------------------
echo "==> Linking dotfiles..."
bash "$DOTFILES_DIR/scripts/symlink.sh"

# ------------------------------------------------------------------
# 13. XDG desktop portals
# ------------------------------------------------------------------
sudo systemctl --global enable xdg-desktop-portal || true

echo ""
echo "==> Desktop setup complete."
echo "    Log out and back in (or reboot) to start the Hyprland session."
echo "    NOTE: If you changed your login shell to fish, re-login for it to take effect."
