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

# Create default configs from examples if neither config exists
for example in "$SOURCE_DIR"/*.conf.example; do
  [ -f "$example" ] || continue
  basename=$(basename "$example" .conf.example)
  short=${basename%-dashboard}
  config="$HOME/.xbar-${short}.conf"
  local_config="$HOME/.xbar-${short}.local.conf"

  if [ ! -f "$config" ] && [ ! -f "$local_config" ]; then
    echo "  Creating default $basename config from example."
    cp "$example" "$config"
    echo "  Edit $config or create $local_config for machine-specific setup."
  fi
done

exit 0
