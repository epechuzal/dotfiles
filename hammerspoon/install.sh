#!/bin/sh
#
# Hammerspoon configuration setup
#
# Symlinks all lua files into ~/.hammerspoon/

set -e

HAMMERSPOON_DIR="$HOME/.hammerspoon"
SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ ! -d "$HAMMERSPOON_DIR" ]; then
  echo "  Creating Hammerspoon config directory."
  mkdir -p "$HAMMERSPOON_DIR"
fi

for src in "$SOURCE_DIR"/*.lua; do
  filename=$(basename "$src")
  dst="$HAMMERSPOON_DIR/$filename"

  if [ -f "$dst" ] && [ ! -L "$dst" ]; then
    echo "  Backing up existing $filename."
    mv "$dst" "$dst.backup"
  fi

  if [ ! -L "$dst" ] || [ "$(readlink "$dst")" != "$src" ]; then
    echo "  Symlinking $filename."
    ln -sf "$src" "$dst"
  fi
done

exit 0
