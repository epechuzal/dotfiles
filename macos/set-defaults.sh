# Sets reasonable macOS defaults.
#
# Or, in other words, set shit how I like in macOS.
#
# The original idea (and a couple settings) were grabbed from:
#   https://github.com/mathiasbynens/dotfiles/blob/master/.macos
#
# Run ./set-defaults.sh and you'll be good to go.

if test ! "$(uname)" = "Darwin"
  then
  exit 0
fi

# Disable press-and-hold for keys in favor of key repeat.
defaults write -g ApplePressAndHoldEnabled -bool false

# Use AirDrop over every interface. srsly this should be a default.
defaults write com.apple.NetworkBrowser BrowseAllInterfaces 1

# Always open everything in Finder's list view. This is important.
defaults write com.apple.Finder FXPreferredViewStyle Nlsv

# Show the ~/Library folder.
chflags nohidden ~/Library

# Set a really fast key repeat.
defaults write NSGlobalDomain KeyRepeat -int 1

# Set the Finder prefs for showing a few different volumes on the Desktop.
defaults write com.apple.finder ShowExternalHardDrivesOnDesktop -bool true
defaults write com.apple.finder ShowRemovableMediaOnDesktop -bool true

# Run the screensaver if we're in the bottom-left hot corner.
defaults write com.apple.dock wvous-bl-corner -int 5
defaults write com.apple.dock wvous-bl-modifier -int 0

# Hide Safari's bookmark bar.
# Note: Safari defaults may fail without Full Disk Access due to macOS sandboxing.
defaults write com.apple.Safari ShowFavoritesBar -bool false 2>/dev/null || true

# Set up Safari for development.
defaults write com.apple.Safari IncludeInternalDebugMenu -bool true 2>/dev/null || true
defaults write com.apple.Safari IncludeDevelopMenu -bool true 2>/dev/null || true
defaults write com.apple.Safari WebKitDeveloperExtrasEnabledPreferenceKey -bool true 2>/dev/null || true
defaults write com.apple.Safari "com.apple.Safari.ContentPageGroupIdentifier.WebKit2DeveloperExtrasEnabled" -bool true 2>/dev/null || true
defaults write NSGlobalDomain WebKitDeveloperExtras -bool true

# Save screenshots to iCloud Drive
mkdir -p ~/Library/Mobile\ Documents/com~apple~CloudDocs/Screenshots
defaults write com.apple.screencapture location "~/Library/Mobile Documents/com~apple~CloudDocs/Screenshots"

# Swap screenshot shortcuts for selected area:
# Cmd+Shift+4 → copy to clipboard (default is save to file)
# Ctrl+Cmd+Shift+4 → save to file (default is copy to clipboard)
defaults write com.apple.symbolichotkeys.plist AppleSymbolicHotKeys -dict-add 30 '<dict><key>enabled</key><true/><key>value</key><dict><key>parameters</key><array><integer>52</integer><integer>21</integer><integer>1441792</integer></array><key>type</key><string>standard</string></dict></dict>'
defaults write com.apple.symbolichotkeys.plist AppleSymbolicHotKeys -dict-add 31 '<dict><key>enabled</key><true/><key>value</key><dict><key>parameters</key><array><integer>52</integer><integer>21</integer><integer>1179648</integer></array><key>type</key><string>standard</string></dict></dict>'

# AltTab preferences
defaults write com.lwouis.alt-tab-macos appearanceStyle -int 2
defaults write com.lwouis.alt-tab-macos appearanceTheme -int 1
defaults write com.lwouis.alt-tab-macos holdShortcut -string "⌘"
defaults write com.lwouis.alt-tab-macos shortcutCount -int 2
defaults write com.lwouis.alt-tab-macos shortcutStyle -int 1
defaults write com.lwouis.alt-tab-macos showAppsOrWindows -int 1
defaults write com.lwouis.alt-tab-macos showTitles -int 2
defaults write com.lwouis.alt-tab-macos titleTruncation -int 2
defaults write com.lwouis.alt-tab-macos mouseHoverEnabled -bool true
defaults write com.lwouis.alt-tab-macos previewFocusedWindow -bool true
defaults write com.lwouis.alt-tab-macos screensToShow -int 0
defaults write com.lwouis.alt-tab-macos windowOrder -int 2
defaults write com.lwouis.alt-tab-macos startAtLogin -bool true
defaults write com.lwouis.alt-tab-macos menubarIconShown -bool true
defaults write com.lwouis.alt-tab-macos blacklist -string '[{"ignore":"0","bundleIdentifier":"com.McAfee.McAfeeSafariHost","hide":"1"},{"ignore":"0","bundleIdentifier":"com.apple.finder","hide":"2"},{"ignore":"2","bundleIdentifier":"com.microsoft.rdc.macos","hide":"0"},{"ignore":"2","bundleIdentifier":"com.teamviewer.TeamViewer","hide":"0"},{"ignore":"2","bundleIdentifier":"org.virtualbox.app.VirtualBoxVM","hide":"0"},{"ignore":"2","bundleIdentifier":"com.parallels.","hide":"0"},{"ignore":"2","bundleIdentifier":"com.citrix.XenAppViewer","hide":"0"},{"ignore":"2","bundleIdentifier":"com.citrix.receiver.icaviewer.mac","hide":"0"},{"ignore":"2","bundleIdentifier":"com.nicesoftware.dcvviewer","hide":"0"},{"ignore":"2","bundleIdentifier":"com.vmware.fusion","hide":"0"},{"ignore":"2","bundleIdentifier":"com.apple.ScreenSharing","hide":"0"},{"ignore":"2","bundleIdentifier":"com.utmapp.UTM","hide":"0"},{"ignore":"0","bundleIdentifier":"com.superduper.superwhisper","hide":"1"},{"ignore":"0","bundleIdentifier":"com.apple.ScreenContinuity","hide":"1"},{"ignore":"0","bundleIdentifier":"com.codeweavers.CrossOver","hide":"1"}]'

# Apply hotkey changes without logout
/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u
