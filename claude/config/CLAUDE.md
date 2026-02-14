# Global Claude Code Configuration

## Permissions

Auto-approved commands (no interruptions):
- **Reading**: cat, ls, echo, head, tail, grep, find, wc, file, stat, awk, sed
- **Shell utils**: test, pwd, which, whoami, env, printenv, dirname, basename, realpath, readlink
- **Git read-only**: status, diff, log, show, branch, remote, config --get, rev-parse, ls-files, ls-tree
- **File reading**: Read tool for any file

Configured in `~/.claude/settings.local.json`

## Critical Rules

### Sensitive Environment Variables
When needing sensitive env vars, look them up in `~/.localrc`

Example: `OP_SERVICE_ACCOUNT_TOKEN`

### Bash Commands
**ALWAYS source the Claude bash profile before running commands:**
```bash
source ~/.claude/profile && <command>
```

This sets up PATH for node/yarn/nx and other dev tools.

**If commands fail** (e.g., after Node upgrade), check and update `~/.claude/profile`.

See `~/.claude/README.md` for details.

## MCP Server Configuration

**Config location:**
```
~/Library/Application Support/Claude/claude_desktop_config.json
```

**Current MCP servers:**
- `google-calendar` - Google Calendar (events, scheduling, free/busy)
- `vikunja` - Task management (projects, tasks, priorities)
- `fastmail` - Email (read, search, label)
- `monarch` - Finance via Monarch Money (transactions, categories, merchants, rules)
- `rowing` - Rowing/Concept2 (Pete Plan progress, workout history)
- `browser` - Browser automation (CDP on port 9222)
- `video-transcribe` - Video transcription
- `youtube` - YouTube (OAuth-authenticated)

**For details on:**
- Creating new MCP servers
- Configuration format
- Server-specific tools and setup

See: `~/Workspace/scinfax/docs/mcp-servers.md`
