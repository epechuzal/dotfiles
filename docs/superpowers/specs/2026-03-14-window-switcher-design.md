# Window Switcher — Design Spec

## Problem

The native macOS Cmd-Tab app switcher has three shortcomings:
1. It operates at the app level, not the window level — useless when you have multiple windows of the same app (especially Ghostty terminals).
2. It shows everything, including background noise (Docker, Spotify, system processes).
3. It provides no preview or context — just app icons.

## Solution

A Hammerspoon-based window switcher activated by a dedicated key on the user's ZSA Voyager keyboard. Tap the key, get a `hs.chooser` list of all interesting windows, pick one, it focuses.

This does **not** replace Cmd-Tab (which continues to serve as a quick MRU toggle). It is a separate, complementary tool for when you need to scan and choose.

## Scope

- Single `hs.chooser`-based list view
- Curated default view with section grouping
- Type-to-search expands to all windows
- No thumbnail/grid mode (Ghostty exposé already covers that use case)
- No hold-and-cycle activation model
- No direct-switch keys (future project, can reuse this module's internals)

## Architecture

### New file: `hammerspoon/switcher.lua`

Standalone module, independent from `orchestrator.lua`. One public function: `M.show()`.

**Imports:**
- `layouts` — `preferredApps`, `hiddenApps`, `repoColors`, `colorPalette`
- `utils` — `findWindows()`, `windowById()`

**Integration in `init.lua`:**
- `local switcher = require("switcher")`
- New speed dial slot bound to `switcher.show()` (key TBD — user will assign on Voyager; needs any free slot on the speed dial grid for testing, e.g., F)

### Window Enumeration

Single enumeration loop: iterate `hs.application.runningApplications()` and collect `app:allWindows()` for every app. This handles Ghostty's one-process-per-window model and all other apps uniformly — no separate code paths. Filter out windows with empty titles within this loop, but do **not** filter `hiddenApps` here — keep the full list cached so search mode can access hidden-app windows. The `hiddenApps` filter is applied only when building the three-tier default view.

Does not use `utils.windowToChoice()` — builds custom choice rows with a different format optimized for cross-app scanning.

For each window, collect:
- Window ID
- App name
- Window title
- Bundle ID (for app icon)
- Screen name
- Minimized state
- For Ghostty: repo name parsed from title (`"repo: branch"` format), repo color from `layouts.repoColors`. Windows whose title doesn't match the `repo: branch` pattern (e.g., scratch terminals) get a dim gray circle fallback.

### Default View (no search query)

Three tiers, assembled in order with non-selectable section header rows:

**1. Favorites**
Windows belonging to apps in `layouts.preferredApps` **except Ghostty** (which appears only in Terminals), ordered by that list's priority. One entry per window (multiple windows of the same app each get their own row).

**2. Terminals**
All Ghostty windows, sorted by `repoColors` priority (matching the existing Ghostty chooser behavior), then alphabetically for repos without a priority entry. Each row gets a colored circle image based on `layouts.repoColors`, with worktree shade hashing for branch variants. This duplicates orchestrator's `colorCircleImage` + `ghosttyChoiceImage` logic (~60 lines total — two callers isn't enough to justify extracting to utils yet). Both files should include a comment pointing to the other copy so changes stay in sync.

**3. Others**
Remaining visible windows not in `layouts.hiddenApps`, sorted alphabetically by app name then window title.

**Section headers** are chooser rows with `valid = false` and dim gray text (e.g., `"── Terminals ──"`). These cannot be selected.

### Search Mode (query entered)

Window enumeration happens once in `show()`. The full flat list (all windows, including hidden apps) is cached for the duration of the chooser session.

On `chooser:queryChangedCallback()`, filter the cached list — do not re-enumerate:
- If query is empty: restore the three-tier default choices
- If query is non-empty: filter the cached flat list by substring match on app name + window title, sorted alphabetically, no section headers

### Row Format

Each selectable row contains:
- **Image:** App bundle icon via `hs.image.imageFromAppBundle(bundleID)`. Ghostty rows use a repo color dot instead (24×24 canvas circle).
- **Text (primary):** Window title
- **SubText (secondary):** App name + screen name. For Ghostty: app name + repo path + window dimensions.

### Selection Behavior

- Select a row: if the window is minimized, call `win:unminimize()`. If the window's app is hidden, call `app:unhide()` (note: this unhides all windows of that app, not just the selected one — matches macOS semantics). Then call `win:focus()`.
- Log the selection to `~/.hammerspoon/usage.log` (consistent with existing orchestrator logging).
- Dismiss: Escape or click outside (native `hs.chooser` behavior).
- No state persistence — window list is rebuilt fresh on every `show()` invocation.

## Configuration

No new configuration. Reuses existing `layouts` tables:
- `layouts.preferredApps` — defines favorites tier and ordering
- `layouts.hiddenApps` — defines what's excluded from default view (still searchable)
- `layouts.repoColors` — Ghostty window color indicators
- `layouts.colorPalette` — RGB values for color dots

Section header labels ("Favorites", "Terminals", "Others") are hardcoded strings in `switcher.lua`.

## What This Does Not Do

- **No Cmd-Tab interception** — uses a dedicated Voyager key instead
- **No thumbnail/preview mode** — the Ghostty exposé grid covers visual disambiguation
- **No hold-and-cycle** — tap-to-open, pick, done
- **No direct-switch keys** — future project that can import from this module
- **No window arrangement** — this is purely a focus switcher
