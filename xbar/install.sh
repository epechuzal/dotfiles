#!/bin/sh
#
# xbar plugin setup
#
# Symlinks plugins into xbar's plugin directory.
# Creates default config if no config exists.
# Cleans up stale symlinks from renamed/removed plugins.

set -e

XBAR_PLUGINS_DIR="$HOME/Library/Application Support/xbar/plugins"
SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ ! -d "$XBAR_PLUGINS_DIR" ]; then
  echo "  Creating xbar plugins directory."
  mkdir -p "$XBAR_PLUGINS_DIR"
fi

# Clean up stale symlinks pointing back to our plugins dir
for dst in "$XBAR_PLUGINS_DIR"/*.sh; do
  [ -L "$dst" ] || continue
  target=$(readlink "$dst")
  case "$target" in
    "$SOURCE_DIR/plugins/"*)
      if [ ! -f "$target" ]; then
        echo "  Removing stale symlink $(basename "$dst")."
        rm "$dst"
      fi
      ;;
  esac
done

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
CONFIG="$HOME/.xbar-infra.conf"
LOCAL_CONFIG="$HOME/.xbar-infra.local.conf"

if [ ! -f "$CONFIG" ] && [ ! -f "$LOCAL_CONFIG" ]; then
  echo "  Creating default infra dashboard config from example."
  cp "$SOURCE_DIR/infra-dashboard.conf.example" "$CONFIG"
  echo "  Edit ~/.xbar-infra.conf or create ~/.xbar-infra.local.conf for machine-specific setup."
fi

exit 0
