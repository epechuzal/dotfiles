#!/bin/sh
#
# Work-specific packages (only when DOTFILES_MACHINE_TYPE=work)

if [ "$DOTFILES_MACHINE_TYPE" != "work" ]; then
  echo "  Skipping work packages (DOTFILES_MACHINE_TYPE=$DOTFILES_MACHINE_TYPE)"
  exit 0
fi

echo "  Installing packages from the work Brewfile."
brew bundle --file="$DOTFILESDIR/work/Brewfile"
