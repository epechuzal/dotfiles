#!/bin/sh
#
# Homebrew
#
# This installs some of the common dependencies needed (or at least desired)
# using Homebrew.

# Check for Homebrew
if test ! $(which brew)
then
  echo "  Installing Homebrew for you."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# Ensure taps are set up before bundling, since brew bundle
# can silently fail to tap and then miss casks from those taps.
echo "  Setting up Homebrew taps."
grep '^tap ' ~/.Brewfile | sed 's/tap "\([^"]*\)".*/\1/' | while read -r t; do
  brew tap "$t" 2>/dev/null || true
done

echo "  Installing packages from the global Brewfile."
brew bundle --global

exit 0
