#!/bin/sh
#
# xbar plugin setup
#
# Symlinks plugins into xbar's plugin directory.
# Creates default config if no config exists.

set -e

XBAR_PLUGINS_DIR="$HOME/Library/Application Support/xbar/plugins"
SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ ! -d "$XBAR_PLUGINS_DIR" ]; then
  echo "  Creating xbar plugins directory."
  mkdir -p "$XBAR_PLUGINS_DIR"
fi

for src in "$SOURCE_DIR/plugins/"*.sh; do
  [ -f "$src" ] || continue
  filename=$(basename "$src")
  dst="$XBAR_PLUGINS_DIR/$filename"

  if [ -f "$dst" ] && [ ! -L "$dst" ]; then
    echo "  Backing up existing $filename."
    mv "$dst" "$dst.backup"
  fi

  if [ ! -L "$dst" ] || [ "$(readlink "$dst")" != "$src" ]; then
    echo "  Symlinking $filename."
    ln -sf "$src" "$dst"
  fi
done

# Create default config from example if neither config exists
CONFIG="$HOME/.xbar-github-actions.conf"
LOCAL_CONFIG="$HOME/.xbar-github-actions.local.conf"

if [ ! -f "$CONFIG" ] && [ ! -f "$LOCAL_CONFIG" ]; then
  echo "  Creating default GitHub Actions config from example."
  cp "$SOURCE_DIR/github-actions.conf.example" "$CONFIG"
  echo "  Edit ~/.xbar-github-actions.conf or create ~/.xbar-github-actions.local.conf for machine-specific repos."
fi

exit 0
