#!/usr/bin/env bash
# Arch Linux installer using archinstall.
# Run from the Arch ISO live environment as root via:  setup install
#
# Steps, in order:
#   1  Validate       refuse to start unless the two JSONs and apps.conf exist
#   2  Inject         merge apps.conf's official-repo packages into the JSON
#   3  archinstall    run the automated installer with the merged config
#
# Only packages ABOVE the "# AUR only" marker in apps.conf are injected:
# archinstall installs with pacman and cannot build from the AUR. Everything
# below that marker is installed later by post-install.sh through paru/yay.
#
# To customize before running:
#   archinstall/user_configuration.json  — disk layout, locale, kernel, mirrors, etc.
#   archinstall/user_credentials.json    — user/root passwords (argon2id-encrypted)
#   packages/apps.conf                   — packages to include in the install
#
# The live ISO is deliberately NOT updated first (`pacman -Syu`): it desyncs the
# live system from the mirror snapshot archinstall then installs from, and on a
# small ISO it can fill the root tmpfs. Update after the first boot instead.

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
# 1. Validate required files
# ------------------------------------------------------------------
for f in "$CONFIG" "$CREDS" "$APPS_CONF"; do
    [[ -f "$f" ]] || { echo "ERROR: required file not found: $f"; exit 1; }
done

# ------------------------------------------------------------------
# 2. Inject packages from apps.conf into user_configuration.json
#    Merges with any packages already present in the JSON (deduplicates).
# ------------------------------------------------------------------
echo "==> Syncing packages from apps.conf into archinstall config..."

# Official-repo section only: awk stops at the "# AUR only" marker.
mapfile -t CONF_PKGS < <(
    awk '/^# AUR only/{exit} !/^\s*#/ && NF {print $1}' "$APPS_CONF" \
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
echo "  2. Log in and run:  setup post"
echo "     (installs AUR helper, multilib, dotfiles, remaining packages)"
