#!/bin/sh
#
# Ghostty configuration setup
#
# Creates ~/.config/ghostty/ and symlinks config

set -e

GHOSTTY_CONFIG_DIR="$HOME/.config/ghostty"
SOURCE_CONFIG="$(cd "$(dirname "$0")" && pwd)/config"

# Create config directory if it doesn't exist
if [ ! -d "$GHOSTTY_CONFIG_DIR" ]; then
  echo "  Creating Ghostty config directory."
  mkdir -p "$GHOSTTY_CONFIG_DIR"
fi

# Symlink config (backup existing if it's a real file, not a symlink)
if [ -f "$GHOSTTY_CONFIG_DIR/config" ] && [ ! -L "$GHOSTTY_CONFIG_DIR/config" ]; then
  echo "  Backing up existing Ghostty config."
  mv "$GHOSTTY_CONFIG_DIR/config" "$GHOSTTY_CONFIG_DIR/config.backup"
fi

if [ ! -L "$GHOSTTY_CONFIG_DIR/config" ]; then
  echo "  Symlinking Ghostty config."
  ln -sf "$SOURCE_CONFIG" "$GHOSTTY_CONFIG_DIR/config"
fi

exit 0
