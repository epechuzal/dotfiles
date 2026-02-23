#!/bin/bash
#
# Claude Code configuration
# Symlinks user-authored config into ~/.claude/ and ensures base settings.

set -e

CLAUDE_DIR="$HOME/.claude"
TOPIC_DIR="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$CLAUDE_DIR"
mkdir -p "$CLAUDE_DIR/skills/bugfix"

# Symlink files that only we edit — tools never touch these
link() {
  local src="$1" dst="$2"
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
    return # already correct
  fi
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    mv "$dst" "${dst}.backup"
    echo "  backed up $dst"
  fi
  ln -s "$src" "$dst"
  echo "  linked $dst"
}

link "$TOPIC_DIR/config/CLAUDE.md"  "$CLAUDE_DIR/CLAUDE.md"
link "$TOPIC_DIR/config/profile"    "$CLAUDE_DIR/profile"
link "$TOPIC_DIR/config/README.md"  "$CLAUDE_DIR/README.md"
link "$TOPIC_DIR/skills/bugfix/SKILL.md" "$CLAUDE_DIR/skills/bugfix/SKILL.md"

# Ensure base settings exist without clobbering tool-managed keys
node "$TOPIC_DIR/ensure-settings.js"
echo "  settings synced"

# Claude Peak – launch on login via LaunchAgent
PLIST_NAME="com.wecouldbe.claude-peak.plist"
LAUNCH_AGENTS="$HOME/Library/LaunchAgents"
mkdir -p "$LAUNCH_AGENTS"
launchctl bootout "gui/$(id -u)/$PLIST_NAME" 2>/dev/null || true
link "$TOPIC_DIR/$PLIST_NAME" "$LAUNCH_AGENTS/$PLIST_NAME"
launchctl bootstrap "gui/$(id -u)" "$LAUNCH_AGENTS/$PLIST_NAME" 2>/dev/null || true
echo "  Claude Peak will start on login"
