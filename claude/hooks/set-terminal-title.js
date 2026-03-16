#!/usr/bin/env node
// Sets terminal title based on user prompt for Hammerspoon window detection
// Title format: repo: branch - <summary of what user asked>
// < 50 chars: verbatim, < 200 chars: truncate, else: ask Haiku

const fs = require('fs');
const path = require('path');
const os = require('os');
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
    const sessionId = data.session_id || '';
    if (!prompt || !sessionId) process.exit(0);

    // Clean up the prompt: collapse whitespace, strip leading slashes
    const clean = prompt.replace(/\s+/g, ' ').trim();
    if (!clean) process.exit(0);

    let summary;
    if (clean.length < 50) {
      summary = clean;
    } else if (clean.length < 200) {
      summary = clean.slice(0, 47) + '...';
    } else {
      // Ask Haiku for a 5-8 word summary
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

    // Write summary to temp file for statusline to pick up
    const summaryPath = path.join(os.tmpdir(), `claude-title-${sessionId}.txt`);
    fs.writeFileSync(summaryPath, summary);

  } catch (e) {
    // Silent fail
  }
});
