#!/usr/bin/env bash
# Arch Linux installer using archinstall.
# Run from the Arch ISO live environment as root via:  setup install
#
# What it does:
#   1. pacman -Syu          — updates the live ISO before installing
#   2. Injects packages     — reads packages/apps.conf and merges into the JSON
#   3. archinstall          — runs the automated installer with the merged config
#
# To customize before running:
#   archinstall/user_configuration.json  — disk layout, locale, kernel, mirrors, etc.
#   archinstall/user_credentials.json   — user/root passwords (argon2id-encrypted)
#   packages/apps.conf                  — pacman packages to include in the install

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

CONFIG="$SCRIPT_DIR/archinstall/user_configuration.json"
CREDS="$SCRIPT_DIR/archinstall/user_credentials.json"
APPS_CONF="$REPO_ROOT/packages/apps.conf"

LOG_FILE="$REPO_ROOT/arch-install.log"
exec > >(tee "$LOG_FILE") 2>&1

echo "=== Arch Linux Installer (archinstall) ==="
echo "Log: $LOG_FILE"
echo ""

# ------------------------------------------------------------------
# Validate required files
# ------------------------------------------------------------------
for f in "$CONFIG" "$CREDS" "$APPS_CONF"; do
    [[ -f "$f" ]] || { echo "ERROR: required file not found: $f"; exit 1; }
done

# ------------------------------------------------------------------
# 1. Update live system
# ------------------------------------------------------------------
echo "==> Updating live system..."
pacman -Syu --noconfirm

# ------------------------------------------------------------------
# 2. Inject packages from apps.conf into user_configuration.json
#    Merges with any packages already present in the JSON (deduplicates).
# ------------------------------------------------------------------
echo "==> Syncing packages from apps.conf into archinstall config..."

# Parse apps.conf: strip comments, blank lines, and inline comments
mapfile -t CONF_PKGS < <(
    grep -v '^\s*#' "$APPS_CONF" \
    | awk 'NF {print $1}' \
    | grep -v '^$'
)

# Build merged package list (JSON existing + apps.conf), deduplicated
python3 - "$CONFIG" "${CONF_PKGS[@]}" <<'PY'
import json, sys

config_path = sys.argv[1]
new_pkgs    = sys.argv[2:]

with open(config_path) as f:
    cfg = json.load(f)

existing = cfg.get("packages", [])
merged   = sorted(set(existing) | set(new_pkgs))
cfg["packages"] = merged

with open(config_path, "w") as f:
    json.dump(cfg, f, indent=4, ensure_ascii=False)

print(f"  packages: {len(merged)} total ({len(new_pkgs)} from apps.conf, {len(existing)} previously in JSON)")
PY

# ------------------------------------------------------------------
# 3. Run archinstall
# ------------------------------------------------------------------
echo ""
echo "==> Starting archinstall..."
echo "    Config : $CONFIG"
echo "    Creds  : $CREDS"
echo ""

archinstall --config "$CONFIG" --creds "$CREDS"

echo ""
echo "==> Installation complete."
echo ""
echo "Next steps:"
echo "  1. Reboot into the new system"
echo "  2. Log in and run:  setup post-install"
echo "     (installs AUR helper, multilib, dotfiles, remaining packages)"
