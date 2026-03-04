#!/bin/sh
#
# SSH configuration setup
#
# Symlinks config into ~/.ssh/

set -e

SSH_DIR="$HOME/.ssh"
SOURCE_CONFIG="$(cd "$(dirname "$0")" && pwd)/config"

if [ ! -d "$SSH_DIR" ]; then
  echo "  Creating .ssh directory."
  mkdir -p "$SSH_DIR"
  chmod 700 "$SSH_DIR"
fi

if [ -f "$SSH_DIR/config" ] && [ ! -L "$SSH_DIR/config" ]; then
  echo "  Backing up existing SSH config to config.local."
  mv "$SSH_DIR/config" "$SSH_DIR/config.local"
fi

if [ ! -L "$SSH_DIR/config" ]; then
  echo "  Symlinking SSH config."
  ln -sf "$SOURCE_CONFIG" "$SSH_DIR/config"
fi

exit 0
