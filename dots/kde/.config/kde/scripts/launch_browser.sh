#!/usr/bin/env bash
# Single source of truth for the browser preference order. Launches the first
# installed browser. With --incognito, opens it in its private/incognito mode.
# Each entry is "binary|incognito-flag". Delegates the "first available" logic
# to launch_first_available.sh.
browsers=(
    "brave|--incognito"
    "google-chrome-stable|--incognito"
    "zen-browser|--private-window"
    "firefox|--private-window"
    "chromium|--incognito"
    "microsoft-edge-stable|--inprivate"
    "opera|--private"
    "librewolf|--private-window"
)

incognito=false
[[ "$1" == "--incognito" ]] && incognito=true

args=()
for entry in "${browsers[@]}"; do
    bin="${entry%%|*}"
    flag="${entry#*|}"
    if [[ "$incognito" == true ]]; then
        args+=("$bin $flag")
    else
        args+=("$bin")
    fi
done

exec "$(dirname "$0")/launch_first_available.sh" "${args[@]}"
