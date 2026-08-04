#!/usr/bin/env bash

QUICKSHELL_CONFIG_NAME="prism"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
CONFIG_DIR="$XDG_CONFIG_HOME/quickshell/$QUICKSHELL_CONFIG_NAME"
CACHE_DIR="$XDG_CACHE_HOME/quickshell"
STATE_DIR="$XDG_STATE_HOME/quickshell"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERMINAL_THEME_DIR="$STATE_DIR/user/generated/terminal"

CONFIG_FILE="$XDG_CONFIG_HOME/settings/quickshell/config.json"
term_alpha=100
if [ -f "$CONFIG_FILE" ]; then
  _opacity=$(jq -r '.appearance.wallpaperTheming.terminalGenerationProps.opacity // 1.0' "$CONFIG_FILE" 2>/dev/null)
  if [ -n "$_opacity" ] && [ "$_opacity" != "null" ]; then
    term_alpha=$(awk "BEGIN{printf \"%.0f\", $_opacity * 100}")
  fi
fi

if [ ! -d "$STATE_DIR"/user/generated ]; then
  mkdir -p "$STATE_DIR"/user/generated
fi
cd "$CONFIG_DIR" || exit

colornames=''
colorstrings=''
colorlist=()
colorvalues=()

colornames=$(cat $STATE_DIR/user/generated/material_colors.scss | cut -d: -f1)
colorstrings=$(cat $STATE_DIR/user/generated/material_colors.scss | cut -d: -f2 | cut -d ' ' -f2 | cut -d ";" -f1)
IFS=$'\n'
colorlist=($colornames)     # Array of color names
colorvalues=($colorstrings) # Array of color values

apply_kitty() {  
  # Check if terminal escape sequence template exists
  if [ ! -f "$SCRIPT_DIR/terminal/kitty-theme.conf" ]; then
    echo "Template file not found for Kitty theme. Skipping that."
    return
  fi
  # Copy template
  mkdir -p "$TERMINAL_THEME_DIR"
  cp "$SCRIPT_DIR/terminal/kitty-theme.conf" "$TERMINAL_THEME_DIR"/kitty-theme.conf
  # Apply colors
  for i in "${!colorlist[@]}"; do
    sed -i "s/${colorlist[$i]} #/${colorvalues[$i]#\#}/g" "$TERMINAL_THEME_DIR"/kitty-theme.conf
  done

  # Apply opacity
  _kitty_opacity=$(awk "BEGIN{printf \"%.2f\", $term_alpha / 100}")
  echo "background_opacity $_kitty_opacity" >> "$TERMINAL_THEME_DIR/kitty-theme.conf"

  # Reload
  if ! pgrep -f kitty >/dev/null; then
    return
  fi
  kill -SIGUSR1 $(pidof kitty)
}

apply_anyterm() {
  # Check if terminal escape sequence template exists
  if [ ! -f "$SCRIPT_DIR/terminal/sequences.txt" ]; then
    echo "Template file not found for Terminal. Skipping that."
    return
  fi
  # Copy template
  mkdir -p "$TERMINAL_THEME_DIR"
  cp "$SCRIPT_DIR/terminal/sequences.txt" "$TERMINAL_THEME_DIR"/sequences.txt
  # Apply colors
  for i in "${!colorlist[@]}"; do
    sed -i "s/${colorlist[$i]} #/${colorvalues[$i]#\#}/g" "$TERMINAL_THEME_DIR"/sequences.txt
  done

  sed -i "s/\$alpha/$term_alpha/g" "$TERMINAL_THEME_DIR/sequences.txt"

  for file in /dev/pts/*; do
    if [[ $file =~ ^/dev/pts/[0-9]+$ ]]; then
      {
      cat "$TERMINAL_THEME_DIR"/sequences.txt >"$file"
      } & disown || true
    fi
  done
}

apply_term() {
  apply_anyterm &
  apply_kitty &
}

# Check if terminal theming is enabled in config
if [ -f "$CONFIG_FILE" ]; then
  enable_terminal=$(jq -r '.appearance.wallpaperTheming.enableTerminal' "$CONFIG_FILE")
  if [ "$enable_terminal" = "true" ]; then
    apply_term &
  fi
else
  echo "Config file not found at $CONFIG_FILE. Applying terminal theming by default."
  apply_term &
fi

# apply_qt & # Qt theming is already handled by kde-material-colors
