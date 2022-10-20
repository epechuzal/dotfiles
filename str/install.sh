#!/bin/sh
#
# Homebrew
#
# This installs some of the common dependencies needed (or at least desired)
# using Homebrew.

if [ -z "$INSTALL_STR_BREWFILE" ]; then
  echo "  INSTALL_STR_BREWFILE env var is not set. Will not install STR Brewfile."
else 
  echo "  Installing packages from the STR Brewfile."

  brew bundle --file="$DOTFILESDIR/str/Brewfile"
fi
