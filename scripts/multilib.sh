#!/usr/bin/env bash
# Enable the multilib repository in /etc/pacman.conf.
# multilib provides 32-bit libraries required by Steam and some games.

set -Eeuo pipefail

PACMAN_CONF="/etc/pacman.conf"

# Check if multilib is already enabled (section header is uncommented)
if grep -q '^\[multilib\]' "$PACMAN_CONF"; then
    echo "multilib is already enabled, skipping"
    exit 0
fi

echo "Enabling multilib repository..."

# Uncomment the [multilib] section header and its Include directive.
# The sed script matches the commented header, removes the #, advances to the
# next line, then removes the # from the Include line.
sudo sed -i '/^#\[multilib\]/{
    s/^#//
    n
    s/^#Include/Include/
}' "$PACMAN_CONF"

# Refresh package databases to pick up the new repository
sudo pacman -Sy

echo "multilib enabled"
