#!/usr/bin/env node
//
// Ensures ~/.claude/settings.json contains at least the keys/values
// from settings-base.json, without removing anything tools have added.
//
// Merge rules:
//   Arrays  → union (add missing items, keep extras)
//   Objects → deep merge recursively
//   Scalars → base wins (these are your explicit preferences)

const fs = require('fs');
const path = require('path');

const SETTINGS = path.join(process.env.HOME, '.claude', 'settings.json');
const BASE = path.join(__dirname, 'settings-base.json');

function merge(target, base) {
  const result = { ...target };
  for (const [key, val] of Object.entries(base)) {
    if (Array.isArray(val)) {
      const existing = Array.isArray(result[key]) ? result[key] : [];
      result[key] = [...new Set([...existing, ...val])];
    } else if (val && typeof val === 'object') {
      result[key] = merge(result[key] || {}, val);
    } else {
      result[key] = val;
    }
  }
  return result;
}

let existing = {};
try {
  existing = JSON.parse(fs.readFileSync(SETTINGS, 'utf8'));
} catch {
  // File doesn't exist or isn't valid JSON — start fresh
}

const base = JSON.parse(fs.readFileSync(BASE, 'utf8'));
const merged = merge(existing, base);

fs.mkdirSync(path.dirname(SETTINGS), { recursive: true });
fs.writeFileSync(SETTINGS, JSON.stringify(merged, null, 2) + '\n');
