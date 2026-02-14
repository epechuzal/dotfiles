# Claude Code Configuration

This directory contains configuration files for Claude Code.

## Files

### `CLAUDE.md`
User instructions and context that Claude reads at the start of every conversation. This is where you put:
- Project-specific workflows
- Preferences and conventions
- Shortcuts to frequently used files or commands
- References to other config files (like `profile`)

### `profile`
Bash profile that Claude sources before running commands. This ensures Claude has access to the same tools you do (node, yarn, nx, etc.).

**Why does Claude need its own profile?**
- Claude's bash environment doesn't automatically load your `~/.zshrc` or `~/.bashrc`
- Tools installed via nvm, rbenv, pyenv, etc. need PATH setup
- This file makes those tools available to Claude

**What's in it?**
- Node.js PATH (via nvm)
- Any other environment variables or aliases Claude needs

**When to update it?**
- After upgrading Node.js (update the version path)
- When adding new development tools that need PATH setup
- When Claude needs access to specific environment variables

**How Claude uses it:**
```bash
source ~/.claude/profile && <your command>
```

## Adding New Configuration

If you want Claude to know something globally (across all projects):
1. Add instructions to `CLAUDE.md`
2. Add environment setup to `profile`
3. Commit and document the change
