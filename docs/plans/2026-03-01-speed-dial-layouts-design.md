# Speed Dial Layouts Design

## Summary

Replace the current ad-hoc modal bindings with a 3x3 speed dial grid mapped to the front 9 keyboard keys. Same trigger (hold ctrl+cmd 0.4s or ctrl+cmd+`), but actions are organized spatially on the keyboard.

## Speed Dial Grid

```
Q  IDE for Ghostty     W  (unbound)     E  (unbound)
A  Tacitus             S  (unbound)     D  (unbound)
Z  Template chooser    X  60/40 split   C  Tile frontmost app (toggle)
```

Row philosophy:
- **Top (Q W E)**: Quirky/app-specific workflows
- **Middle (A S D)**: Named layouts (specific app combos in fixed positions)
- **Bottom (Z X C)**: Generic utilities that work with whatever's open

## Actions

### Q — IDE for Ghostty
Existing flow, unchanged. Pick a Ghostty window, derive dir, open WebStorm, arrange 60/40.

### A — Tacitus
Existing named layout: Obsidian 60% left + Ghostty (tacitus) 40% right. (Changed from 2/3+1/3 to 60/40.)

### Z — Template Chooser
Existing template chooser, unchanged. Opens chooser with layout templates to pick from.

### X — 60/40 Split
Instant action, no chooser. Takes the two most recently focused windows and arranges them 60% left, 40% right on the current screen.

### C — Tile Frontmost App (Toggle)

Finds all windows of the frontmost app on the current screen (scanning all process instances to handle apps like Ghostty that run separate processes per window).

**Tiling rules by window count:**
- 1: full screen
- 2: 50/50 left/right
- 3: equal thirds (vertical strips)
- 4: 2x2 quadrants
- 5+: fanned cascade — each window offset so every title bar/left edge is clickable, like a fanned deck of cards. Offset calculated as `(screen_width - min_window_width) / (count - 1)`.

**Toggle behavior:**
- First press: store snapshot (each window's frame + minimized state), then tile.
- Second press (same app, same screen): restore from snapshot, clear it.
- If windows have changed since snapshot (opened/closed), discard snapshot and do a fresh tile.

**Screen scoping:** Only tiles windows on the screen where the frontmost window lives. Windows of the same app on other screens are untouched.

### Unbound Slots (W, E, S, D)
Left empty. Easy to fill later via the `speedDial` table in `init.lua` or via `local.lua` overrides. Shown as dim/empty in the cheat sheet.

## Other Changes

### 60/40 Everywhere
All existing 2/3 + 1/3 splits changed to 0.6/0.4:
- `tacitus` named layout in `layouts.lua`
- "2/3 Left + 1/3 Right" template → "60/40 Left + Right"
- "2/3 Left + 2 Stacked Right" template → "60 Left + 2 Stacked Right"

### Cheat Sheet
Reformatted as a 3x3 grid matching the physical keyboard layout. Unbound slots shown dim. R (reload) kept as a modal binding but not in the speed dial grid.

### Architecture
- `speedDial` table in `init.lua` maps each of the 9 keys to `{label, fn}` (or nil for unbound).
- Modal binds all 9 keys from this table.
- Cheat sheet renders from the same table.
- `local.lua` can override/extend the table.
- Tile snapshot state lives in `orchestrator.lua` as a module-level table.
