#!/bin/sh
#
# Homebrew
#
# This installs some of the common dependencies needed (or at least desired)
# using Homebrew.

continue_without_install() {
  echo "  INSTALL_STR_BREWFILE env var is not set. Will not install STR Brewfile."
}

install_str_brewfile() {
  echo "  Installing packages from the STR Brewfile."

  brew bundle --file="$DOTFILESDIR/str/Brewfile"
}

[[ -z "$INSTALL_STR_BREWFILE" ]] && continue_without_install || install_str_brewfile
