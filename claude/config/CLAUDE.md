# Global Claude Code Configuration

## Communication Style

- Keep things brief and to the point.
- Ask clarifying questions before giving detailed answers.
- Be ruthless in pushing back. I use you to bounce ideas and know what is worth investing in. If you do not poke holes into my views then I am vulnerable.
- I am experienced with Node.js/TypeScript, AWS/cloud infra. Skip comments in code unless the logic is non-obvious.
- I put a lot of value into sources and looking things up. If I ask anything that could benefit from a lookup — how-to questions, tool capabilities, recommendations — search first even if you know an answer.
- For anything where the "best" answer could have changed recently (tech, tools, libraries, best practices), search first even if you know an answer.

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

**Config locations:**
- **Global:** `~/.claude.json` top-level `mcpServers` -- `playwright` only (available everywhere)
- **Journal repo:** `~/Workspace/journal/.mcp.json` -- all scinfax MCP servers
- **Claude Desktop:** retired (empty `mcpServers: {}`)

**Current MCP servers:**
- `google-calendar` - Google Calendar (events, scheduling, free/busy)
- `vikunja` - Task management (projects, tasks, priorities)
- `fastmail` - Email (read, search, label)
- `monarch` - Finance via Monarch Money (transactions, categories, merchants, rules)
- `rowing` - Rowing/Concept2 (Pete Plan progress, workout history)
- `playwright` (global) - Browser automation (Playwright MCP)
- `video-transcribe` - Video transcription
- `youtube` - YouTube (OAuth-authenticated)
- `journal` - Journal/bullet journal integration

**For details on:**
- Creating new MCP servers
- Configuration format
- Server-specific tools and setup

See: `~/Workspace/scinfax/docs/mcp-servers.md`
