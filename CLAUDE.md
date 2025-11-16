# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a topic-based dotfiles repository forked from Zach Holman's dotfiles. It manages shell configuration (zsh), macOS defaults, Homebrew packages, and various development tools through a modular, topic-centric architecture.

**Key Principle**: Files are organized by topic (git, ruby, system, etc.) rather than having one monolithic config file.

## Initial Setup

```bash
# Clone and bootstrap (first time setup)
git clone https://github.com/holman/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
script/bootstrap
```

The bootstrap script will:
1. Create `git/gitconfig.local.symlink` with your git credentials
2. Symlink all `*.symlink` files to `$HOME` (e.g., `git/gitconfig.symlink` → `~/.gitconfig`)
3. Run `bin/dot` to install dependencies and set macOS defaults

## Common Commands

### Update System
```bash
dot                    # Updates homebrew, runs installers, sets macOS defaults
dot --edit            # Open dotfiles in $EDITOR
```

### Bootstrap Actions
```bash
script/bootstrap      # Initial setup - symlinks dotfiles and runs installers
script/install        # Runs all topic install.sh scripts
```

## File Structure & Conventions

### Special File Patterns

Files with specific names or extensions have special behaviors:

- **`bin/*`**: Executables added to `$PATH` globally
- **`topic/*.zsh`**: Auto-loaded into zsh environment
- **`topic/path.zsh`**: Loaded FIRST (sets up `$PATH`)
- **`topic/completion.zsh`**: Loaded LAST (sets up autocomplete)
- **`topic/install.sh`**: Executed by `script/install` (not auto-loaded)
- **`topic/*.symlink`**: Symlinked to `$HOME/.{basename}` by `script/bootstrap`

### Topic Directories

Each directory represents a topic area:
- **git/**: Git configuration, aliases, and custom git commands
- **zsh/**: Zsh shell configuration (loaded by `~/.zshrc`)
- **homebrew/**: Homebrew installation and package management
- **macos/**: macOS system preferences via `defaults` commands
- **system/**: General system aliases, environment variables, key bindings
- **functions/**: Zsh completion functions and utility functions
- **bin/**: Executable scripts available globally
- **ruby/**, **node/**, **docker/**, etc.: Language/tool-specific configs

## Important Variables

**`$DOTFILESDIR`**: Points to `~/Workspace/dotfiles` (set in `zsh/zshrc.symlink` and `bin/dot`)
**`$PROJECTS`**: Points to `~/Workspace` for project navigation

## Architecture Details

### Zsh Loading Order

The `zsh/zshrc.symlink` loads configuration in this specific order:

1. Sources `~/.localrc` if it exists (for private environment variables)
2. Loads all `*/path.zsh` files first (PATH setup)
3. Loads all other `*.zsh` files except path.zsh and completion.zsh
4. Initializes zsh autocomplete (`compinit`)
5. Loads all `*/completion.zsh` files last

### Homebrew Package Management

- **Global Brewfile**: Located at `~/.Brewfile` (managed as Brewfile.symlink)
- **Topic-specific**: Each topic can have `install.sh` that installs packages
- **STR Brewfile**: Optional work-specific packages in `str/Brewfile` (requires `$INSTALL_STR_BREWFILE` env var)

The `homebrew/install.sh` script:
- Installs Homebrew if not present
- Runs `brew bundle --global` to install from `~/.Brewfile`

### Git Configuration

Git config is split into two files:
- **`git/gitconfig.symlink`**: Public config (aliases, colors, editor) committed to repo
- **`git/gitconfig.local.symlink`**: Private config (name, email) NOT committed (in .gitignore)

During `script/bootstrap`, if `git/gitconfig.local.symlink` doesn't exist, it prompts for:
- GitHub author name
- GitHub author email
- Creates the local config from template

### Custom Git Commands

All `bin/git-*` scripts become git subcommands:
- `git-promote` → `git promote` (push branch and open PR)
- `git-wtf` → `git wtf` (show branch status)
- `git-rank-contributors` → `git rank-contributors`
- Many more in `bin/`

### macOS Defaults

The `macos/set-defaults.sh` script sets system preferences:
- Fast key repeat
- Finder list view by default
- Show hidden Library folder
- Safari developer tools
- Dock hot corners
- And more...

Run via `dot` command or directly: `./macos/set-defaults.sh`

## Secret Management

There's a plan (`PLAN-1password-secrets.md`) to integrate 1Password for managing `~/.localrc`:
- Uses 1Password CLI (`op`)
- Service account token stored in `.localrc` itself (bootstraps itself)
- Pulls secrets from 1Password on setup

**Current approach**: Manually maintain `~/.localrc` with sensitive env vars (not committed).

## Adding New Topics

To add a new topic (e.g., "python"):

1. Create directory: `mkdir python`
2. Add files following conventions:
   - `python/path.zsh` - Add python binaries to PATH
   - `python/aliases.zsh` - Python-related aliases
   - `python/install.sh` - Install python packages
   - `python/config.symlink` - Symlink to `~/.config`
3. Files will be auto-discovered and loaded by zsh on next shell start

## Working with This Repo

### Before Making Changes

1. **Test changes locally**: Source the file or restart shell to test
2. **Check for dependencies**: Some scripts expect `$DOTFILESDIR` or specific tools
3. **Verify symlinks**: Remember that `.symlink` files are symlinked to `$HOME`

### Common Tasks

**Update a zsh alias**:
- Edit the appropriate `topic/aliases.zsh` file
- Restart terminal or run `source ~/.zshrc`

**Add a new executable script**:
- Add to `bin/` directory
- Make executable: `chmod +x bin/script-name`
- Will be available globally after restarting shell

**Update Homebrew packages**:
- Edit `~/.Brewfile` (which is a symlink to a `.symlink` file in a topic)
- Run `brew bundle --global` or just `dot`

**Change git config**:
- Public settings: Edit `git/gitconfig.symlink`
- Private settings: Edit `git/gitconfig.local.symlink` (not in repo)

## Notes

- **Private data**: Use `~/.localrc` for private environment variables (sourced by zshrc)
- **macOS-specific**: Many scripts check `uname` and skip on non-Darwin systems
- **Dotfiles path**: Hardcoded to `~/Workspace/dotfiles` in `bin/dot`
- **Git default branch**: Set to `main` in gitconfig
