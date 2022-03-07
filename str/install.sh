#!/bin/sh
#
# Homebrew
#
# This installs some of the common dependencies needed (or at least desired)
# using Homebrew.

prompt () {
  printf "\r  [ \033[0;33m??\033[0m ] $1\n"
}

install_str_brewfile() {
  echo "  Installing packages from the STR Brewfile."

  brew bundle --file="$DOTFILESDIR/str/Brewfile"

  exit 0
}

prompt ' - Install Sharethrough Brewfile? [y/N]'
read -n 1 action

case "$action" in
  y|Y )
   install_str_brewfile;;
  * )
    exit 0;;
esac
