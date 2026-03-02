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

# Claude Code – install native binary on non-macOS (macOS uses brew cask)
if [ "$(uname -s)" != "Darwin" ] && ! command -v claude > /dev/null 2>&1; then
  echo "  Installing Claude Code CLI."
  curl -fsSL https://claude.ai/install.sh | bash
fi

# LSP language servers — used by Claude Code plugins
if ! command -v typescript-language-server &>/dev/null; then
  npm install -g typescript typescript-language-server
  echo "  installed typescript-language-server"
else
  echo "  typescript-language-server already installed"
fi

if ! command -v pyright &>/dev/null; then
  uv tool install pyright
  echo "  installed pyright"
else
  echo "  pyright already installed"
fi

# Claude Code LSP plugins
if command -v claude &>/dev/null; then
  PLUGINS_FILE="$CLAUDE_DIR/plugins/installed_plugins.json"

  if ! grep -q "typescript-lsp" "$PLUGINS_FILE" 2>/dev/null; then
    claude plugin install typescript-lsp@claude-plugins-official
    echo "  installed typescript-lsp plugin"
  else
    echo "  typescript-lsp plugin already installed"
  fi

  if ! grep -q "pyright-lsp" "$PLUGINS_FILE" 2>/dev/null; then
    claude plugin install pyright-lsp@claude-plugins-official
    echo "  installed pyright-lsp plugin"
  else
    echo "  pyright-lsp plugin already installed"
  fi

  if ! grep -q "code-simplifier" "$PLUGINS_FILE" 2>/dev/null; then
    claude plugin install code-simplifier@claude-plugins-official
    echo "  installed code-simplifier plugin"
  else
    echo "  code-simplifier plugin already installed"
  fi

  if ! grep -q "superpowers" "$PLUGINS_FILE" 2>/dev/null; then
    claude plugin install superpowers@claude-plugins-official
    echo "  installed superpowers plugin"
  else
    echo "  superpowers plugin already installed"
  fi

  # GSD (Get Shit Done) — spec-driven development framework
  if [ ! -f "$CLAUDE_DIR/gsd-file-manifest.json" ]; then
    npx get-shit-done-cc --claude --global
    echo "  installed GSD"
  else
    echo "  GSD already installed"
  fi
else
  echo "  ⚠ claude CLI not found — skipping plugin and GSD install"
fi

# Claude Peak – launch on login via LaunchAgent (macOS only)
if [ "$(uname -s)" = "Darwin" ]; then
  PLIST_NAME="com.wecouldbe.claude-peak.plist"
  LAUNCH_AGENTS="$HOME/Library/LaunchAgents"
  mkdir -p "$LAUNCH_AGENTS"
  launchctl bootout "gui/$(id -u)/$PLIST_NAME" 2>/dev/null || true
  link "$TOPIC_DIR/$PLIST_NAME" "$LAUNCH_AGENTS/$PLIST_NAME"
  launchctl bootstrap "gui/$(id -u)" "$LAUNCH_AGENTS/$PLIST_NAME" 2>/dev/null || true
  echo "  Claude Peak will start on login"
fi
