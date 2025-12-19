#!/bin/sh
#
# Node.js setup via nvm
#
# Installs nvm, latest LTS node, and global npm packages

set -e

export NVM_DIR="$HOME/.nvm"

# Install nvm if not present
if [ ! -d "$NVM_DIR" ]; then
  echo "  Installing nvm."
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
fi

# Load nvm
. "$NVM_DIR/nvm.sh"

# Install latest LTS and set as default
echo "  Installing latest LTS node version."
nvm install --lts
nvm alias default lts/*

# Install global packages
PACKAGES_FILE="$(dirname "$0")/global-packages"
if [ -f "$PACKAGES_FILE" ]; then
  echo "  Installing global npm packages."
  while IFS= read -r package || [ -n "$package" ]; do
    # Skip empty lines and comments
    case "$package" in
      ""|\#*) continue ;;
    esac
    echo "    Installing $package"
    npm install -g "$package"
  done < "$PACKAGES_FILE"
fi

exit 0
