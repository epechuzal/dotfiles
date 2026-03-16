#!/usr/bin/env node
// Sets terminal title on each user prompt for Hammerspoon window detection.
// Title format: repo: branch - <summary>
// Self-contained — no dependency on GSD or any other statusline.
// < 50 chars: verbatim, < 200 chars: truncate, >= 200: Haiku summary

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

let input = '';
const timeout = setTimeout(() => process.exit(0), 10000);
process.stdin.setEncoding('utf8');
process.stdin.on('data', chunk => input += chunk);
process.stdin.on('end', () => {
  clearTimeout(timeout);
  try {
    const data = JSON.parse(input);
    const prompt = data.prompt || '';
    const cwd = data.cwd || process.cwd();
    if (!prompt) process.exit(0);

    const clean = prompt.replace(/\s+/g, ' ').trim();
    if (!clean) process.exit(0);

    // Get repo name and branch
    let repo, branch;
    try {
      repo = path.basename(execSync('git -C ' + JSON.stringify(cwd) + ' rev-parse --show-toplevel 2>/dev/null', { encoding: 'utf8' }).trim());
      branch = execSync('git -C ' + JSON.stringify(cwd) + ' symbolic-ref --short HEAD 2>/dev/null', { encoding: 'utf8' }).trim();
    } catch (e) {
      repo = path.basename(cwd);
      branch = '';
    }

    // Summarize prompt
    let summary;
    if (clean.length < 50) {
      summary = clean;
    } else if (clean.length < 200) {
      summary = clean.slice(0, 47) + '...';
    } else {
      try {
        const escaped = clean.slice(0, 500).replace(/'/g, "'\\''");
        summary = execSync(
          `echo '${escaped}' | claude -p --model haiku "Summarize this user request in 5-8 lowercase words. Output ONLY the summary, nothing else."`,
          { encoding: 'utf8', timeout: 5000 }
        ).trim();
        if (!summary || summary.length > 60) {
          summary = clean.slice(0, 47) + '...';
        }
      } catch (e) {
        summary = clean.slice(0, 47) + '...';
      }
    }

    // Set terminal title via OSC escape
    const prefix = branch ? `${repo}: ${branch}` : repo;
    const title = `${prefix} - ${summary}`;
    fs.writeFileSync('/dev/tty', `\x1b]0;${title}\x07`);
  } catch (e) {
    // Silent fail
  }
});
