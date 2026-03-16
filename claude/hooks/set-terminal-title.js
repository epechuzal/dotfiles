#!/usr/bin/env node
// Sets terminal title on each user prompt for Hammerspoon window detection.
// Title format: repo: branch - <session summary>
//
// Reads user prompts from CC's own transcript JSONL (via transcript_path).
// Periodically asks Haiku to describe what the session is about.
// Between summaries, shows truncated latest prompt.
//
// Guards:
//   - CLAUDE_TITLE_HOOK_ACTIVE env var prevents recursive hook execution
//   - Minimum 3 prompts before first Haiku call (skip one-shots)
//   - Cooldown (30 min) between subsequent Haiku calls
//   - Skip refresh if no new prompts since last summary
//   - State keyed by session_id

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const COOLDOWN_MS = 30 * 60 * 1000;
const MIN_PROMPTS = 3;
const STATE_DIR = path.join(require('os').tmpdir(), 'claude-title-hook');
// Resolve claude CLI — check common locations
const CLAUDE_CLI = (() => {
  for (const p of [
    path.join(require('os').homedir(), '.local/bin/claude'),
    '/opt/homebrew/bin/claude',
    '/usr/local/bin/claude',
  ]) {
    try { fs.accessSync(p, fs.constants.X_OK); return p; } catch (e) {}
  }
  return 'claude'; // hope it's on PATH
})();

// Recursion guard — claude -p triggers UserPromptSubmit too
if (process.env.CLAUDE_TITLE_HOOK_ACTIVE) process.exit(0);

let input = '';
const timer = setTimeout(() => process.exit(0), 10000);
process.stdin.setEncoding('utf8');
process.stdin.on('data', chunk => input += chunk);
process.stdin.on('end', () => {
  clearTimeout(timer);
  try {
    const data = JSON.parse(input);
    const prompt = data.prompt || '';
    const cwd = data.cwd || process.cwd();
    const sessionId = data.session_id || '';
    const transcriptPath = data.transcript_path || '';
    if (!prompt) process.exit(0);

    const clean = prompt.replace(/\s+/g, ' ').trim();
    if (!clean) process.exit(0);

    // Get repo name (from remote origin, not dir name — works for worktrees)
    let repo, branch;
    try {
      branch = execSync('git -C ' + JSON.stringify(cwd) + ' symbolic-ref --short HEAD 2>/dev/null', { encoding: 'utf8' }).trim();
      const remoteUrl = execSync('git -C ' + JSON.stringify(cwd) + ' remote get-url origin 2>/dev/null', { encoding: 'utf8' }).trim();
      repo = path.basename(remoteUrl, '.git');
    } catch (e) {
      repo = path.basename(cwd);
      branch = '';
    }

    // Load cooldown state (keyed by session)
    fs.mkdirSync(STATE_DIR, { recursive: true });
    const stateFile = sessionId ? path.join(STATE_DIR, `${sessionId}.json`) : '';
    let state = { lastSummary: '', lastSummaryTime: 0, lastPromptCount: 0 };
    if (stateFile) {
      try { state = JSON.parse(fs.readFileSync(stateFile, 'utf8')); } catch (e) {}
    }

    const now = Date.now();
    let summary = state.lastSummary;

    if (transcriptPath) {
      const prompts = extractUserPrompts(transcriptPath, 1500);
      const promptCount = prompts.length;
      const hasEnoughContext = promptCount >= MIN_PROMPTS;
      const neverSummarized = state.lastSummaryTime === 0;
      const cooldownElapsed = now - state.lastSummaryTime >= COOLDOWN_MS;
      const hasNewPrompts = promptCount > state.lastPromptCount;

      // Fire Haiku when:
      //   - enough context (>= 3 prompts) AND
      //   - either never summarized, or (cooldown elapsed AND new prompts)
      const shouldSummarize = hasEnoughContext
        && (neverSummarized || (cooldownElapsed && hasNewPrompts));

      if (shouldSummarize) {
        try {
          const context = prompts.join('\n---\n');
          const escaped = context.replace(/'/g, "'\\''");
          const result = execSync(
            `echo '${escaped}' | CLAUDE_TITLE_HOOK_ACTIVE=1 ${CLAUDE_CLI} -p --model haiku "These are the recent prompts from a coding session. Describe what this session is about in 4-8 lowercase words. Output ONLY the description, nothing else."`,
            { encoding: 'utf8', timeout: 8000 }
          ).trim();
          if (result && result.length <= 60) {
            summary = result;
            state.lastSummary = summary;
            state.lastSummaryTime = now;
          }
        } catch (e) {
          // Haiku failed — keep previous summary
        }
      }

      state.lastPromptCount = promptCount;
    }

    // Save state
    if (stateFile) {
      fs.writeFileSync(stateFile, JSON.stringify(state));
    }

    // Fallback if no summary yet
    if (!summary) {
      summary = clean.length <= 50 ? clean : clean.slice(0, 47) + '...';
    }

    // Set terminal title via OSC escape
    const prefix = branch ? `${repo}: ${branch}` : repo;
    const title = `${prefix} - ${summary}`;
    fs.writeFileSync('/dev/tty', `\x1b]0;${title}\x07`);
  } catch (e) {
    // Silent fail
  }
});

// Read the JSONL transcript tail and extract user prompt texts,
// keeping total chars under maxChars.
function extractUserPrompts(transcriptPath, maxChars) {
  let lines;
  try {
    // Read last ~50KB — enough to get recent prompts without reading huge files
    const fd = fs.openSync(transcriptPath, 'r');
    const stat = fs.fstatSync(fd);
    const readSize = Math.min(stat.size, 50000);
    const buf = Buffer.alloc(readSize);
    fs.readSync(fd, buf, 0, readSize, stat.size - readSize);
    fs.closeSync(fd);
    lines = buf.toString('utf8').split('\n').filter(Boolean);
  } catch (e) {
    return [];
  }

  const prompts = [];
  let totalChars = 0;
  // Walk backwards to get most recent first
  for (let i = lines.length - 1; i >= 0; i--) {
    try {
      const entry = JSON.parse(lines[i]);
      if (entry.type === 'user' && entry.message?.content) {
        const text = (typeof entry.message.content === 'string'
          ? entry.message.content
          : JSON.stringify(entry.message.content)
        ).replace(/\s+/g, ' ').trim();
        if (!text) continue;
        totalChars += text.length;
        if (totalChars > maxChars) break;
        prompts.unshift(text);
      }
    } catch (e) {}
  }
  return prompts;
}
