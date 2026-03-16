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

function mergeArrays(existing, incoming) {
  // For arrays of objects with a "command" field (hook entries),
  // deduplicate by command string
  const hasCommands = incoming.some(v => v && typeof v === 'object' && !Array.isArray(v));
  if (!hasCommands) return [...new Set([...existing, ...incoming])];

  const result = [...existing];
  for (const item of incoming) {
    if (item && typeof item === 'object' && item.hooks) {
      // Hook group — merge hooks arrays within the group
      const existingGroup = result.find(r => r && r.hooks);
      if (existingGroup) {
        const existingCmds = new Set(existingGroup.hooks.map(h => h.command));
        for (const hook of item.hooks) {
          if (!existingCmds.has(hook.command)) {
            existingGroup.hooks.push(hook);
          }
        }
      } else {
        result.push(item);
      }
    } else {
      const serialized = JSON.stringify(item);
      if (!result.some(r => JSON.stringify(r) === serialized)) {
        result.push(item);
      }
    }
  }
  return result;
}

function merge(target, base) {
  const result = { ...target };
  for (const [key, val] of Object.entries(base)) {
    if (Array.isArray(val)) {
      const existing = Array.isArray(result[key]) ? result[key] : [];
      result[key] = mergeArrays(existing, val);
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
