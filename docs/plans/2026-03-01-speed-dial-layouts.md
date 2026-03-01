# Speed Dial Layouts Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace ad-hoc modal bindings with a 3x3 speed dial grid (Q/W/E, A/S/D, Z/X/C) and add two new actions: instant 60/40 split and toggleable tile-frontmost-app.

**Architecture:** A `speedDial` table in `init.lua` maps 9 keys to `{label, fn}`. The modal/cheat sheet render from this table. New tiling logic lives in `orchestrator.lua` with snapshot state for toggle. All 2/3+1/3 splits become 60/40.

**Tech Stack:** Lua, Hammerspoon API (`hs.window`, `hs.screen`, `hs.eventtap`, `hs.hotkey.modal`)

**Note:** No automated test framework — Hammerspoon is tested by reloading config (`ctrl+cmd+` then R`) and exercising the hotkeys manually.

---

### Task 1: Update layouts.lua — 60/40 everywhere

**Files:**
- Modify: `hammerspoon/layouts.lua:4-9` (tacitus named layout)
- Modify: `hammerspoon/layouts.lua:15-19` (first template)
- Modify: `hammerspoon/layouts.lua:44-51` (fifth template)

**Step 1: Change tacitus from 2/3+1/3 to 60/40**

```lua
  tacitus = {
    slots = {
      { app = "Obsidian", position = {0, 0, 0.6, 1} },
      { app = "Ghostty", title = "tacitus", position = {0.6, 0, 0.4, 1} },
    },
  },
```

Also remove the `hotkey` field from tacitus — it's no longer triggered by its own hotkey, only via speed dial.

**Step 2: Rename and update first template**

```lua
  {
    name = "60/40 Left + Right",
    slots = {
      { label = "Left (60%)", position = {0, 0, 0.6, 1} },
      { label = "Right (40%)", position = {0.6, 0, 0.4, 1} },
    },
  },
```

**Step 3: Rename and update fifth template**

```lua
  {
    name = "60 Left + 2 Stacked Right",
    slots = {
      { label = "Left (60%)", position = {0, 0, 0.6, 1} },
      { label = "Top Right (40%)", position = {0.6, 0, 0.4, 0.5} },
      { label = "Bottom Right (40%)", position = {0.6, 0.5, 0.4, 0.5} },
    },
  },
```

**Step 4: Remove templateHotkey**

Delete line 60: `M.templateHotkey = { mods = {"cmd", "ctrl"}, key = "space" }` — no longer used, speed dial handles the binding.

**Step 5: Commit**

```bash
git add hammerspoon/layouts.lua
git commit -m "refactor(hammerspoon): change all 2/3+1/3 splits to 60/40"
```

---

### Task 2: Add quickSplit to orchestrator.lua

**Files:**
- Modify: `hammerspoon/orchestrator.lua` (add function after `activateNamedLayout`)

**Step 1: Add `quickSplit` function**

This takes the two most recently focused windows and arranges them 60/40 on the current screen.

```lua
function M.quickSplit()
  local wins = hs.window.orderedWindows()
  if #wins < 2 then
    hs.alert.show("Need at least 2 windows")
    return
  end

  local first = wins[1]
  local second = wins[2]
  local screen = first:screen()

  utils.positionWindow(first, {0, 0, 0.6, 1}, screen)
  utils.positionWindow(second, {0.6, 0, 0.4, 1}, screen)
  first:focus()

  log("quicksplit:" .. (first:application():name() or "?") .. "+" .. (second:application():name() or "?"))
end
```

**Step 2: Verify manually**

Reload Hammerspoon. (Won't be wired to speed dial yet, but function exists.)

**Step 3: Commit**

```bash
git add hammerspoon/orchestrator.lua
git commit -m "feat(hammerspoon): add quickSplit for instant 60/40"
```

---

### Task 3: Add tileFrontmostApp to orchestrator.lua

**Files:**
- Modify: `hammerspoon/orchestrator.lua` (add tile snapshot state + function)

**Step 1: Add snapshot state at module level**

After `local logFile = ...` line:

```lua
-- Tile toggle snapshot: keyed by "appName:screenId"
local tileSnapshots = {}
```

**Step 2: Add helper to collect app windows on a screen**

```lua
local function appWindowsOnScreen(appName, screen)
  local wins = {}
  for _, app in ipairs(hs.application.runningApplications()) do
    if app:name() == appName then
      for _, win in ipairs(app:allWindows()) do
        local title = win:title() or ""
        if title ~= "" and win:screen():id() == screen:id() then
          table.insert(wins, win)
        end
      end
    end
  end
  return wins
end
```

**Step 3: Add the tile function**

```lua
function M.tileFrontmostApp()
  local frontWin = hs.window.frontmostWindow()
  if not frontWin then
    hs.alert.show("No frontmost window")
    return
  end

  local app = frontWin:application()
  local appName = app and app:name() or ""
  local screen = frontWin:screen()
  local snapshotKey = appName .. ":" .. tostring(screen:id())

  -- Collect windows of this app on this screen
  local wins = appWindowsOnScreen(appName, screen)
  if #wins == 0 then return end

  -- Check for toggle: restore if snapshot exists and windows match
  local snap = tileSnapshots[snapshotKey]
  if snap then
    local snapIds = {}
    for _, s in ipairs(snap) do snapIds[s.id] = true end
    local currentIds = {}
    for _, w in ipairs(wins) do currentIds[w:id()] = true end

    -- Check windows haven't changed
    local match = true
    for id in pairs(snapIds) do
      if not currentIds[id] then match = false; break end
    end
    for id in pairs(currentIds) do
      if not snapIds[id] then match = false; break end
    end

    if match then
      -- Restore
      for _, s in ipairs(snap) do
        local win = hs.window.get(s.id)
        if win then
          win:setFrame(s.frame)
          if s.minimized then win:minimize() end
        end
      end
      tileSnapshots[snapshotKey] = nil
      log("tile-restore:" .. appName .. " (" .. #snap .. " windows)")
      return
    else
      -- Windows changed, discard snapshot
      tileSnapshots[snapshotKey] = nil
    end
  end

  -- Save snapshot
  local snapshot = {}
  for _, win in ipairs(wins) do
    table.insert(snapshot, {
      id = win:id(),
      frame = win:frame(),
      minimized = win:isMinimized(),
    })
  end
  tileSnapshots[snapshotKey] = snapshot

  -- Unminimize all
  for _, win in ipairs(wins) do
    if win:isMinimized() then win:unminimize() end
  end

  local f = screen:frame()
  local count = #wins

  if count == 1 then
    utils.positionWindow(wins[1], {0, 0, 1, 1}, screen)
  elseif count == 2 then
    utils.positionWindow(wins[1], {0, 0, 0.5, 1}, screen)
    utils.positionWindow(wins[2], {0.5, 0, 0.5, 1}, screen)
  elseif count == 3 then
    for i, win in ipairs(wins) do
      utils.positionWindow(win, {(i-1)/3, 0, 1/3, 1}, screen)
    end
  elseif count == 4 then
    utils.positionWindow(wins[1], {0, 0, 0.5, 0.5}, screen)
    utils.positionWindow(wins[2], {0.5, 0, 0.5, 0.5}, screen)
    utils.positionWindow(wins[3], {0, 0.5, 0.5, 0.5}, screen)
    utils.positionWindow(wins[4], {0.5, 0.5, 0.5, 0.5}, screen)
  else
    -- 5+: fanned cascade
    local minW = f.w * 0.5
    local offsetX = (f.w - minW) / (count - 1)
    for i, win in ipairs(wins) do
      win:setFrame({
        x = f.x + (i - 1) * offsetX,
        y = f.y,
        w = minW,
        h = f.h,
      })
    end
  end

  -- Focus the first window last so it's on top
  wins[1]:focus()
  log("tile:" .. appName .. " (" .. count .. " windows)")
end
```

**Step 4: Commit**

```bash
git add hammerspoon/orchestrator.lua
git commit -m "feat(hammerspoon): add tileFrontmostApp with toggle restore"
```

---

### Task 4: Rewrite init.lua with speed dial system

**Files:**
- Modify: `hammerspoon/init.lua` (full rewrite of the modal/binding section)

**Step 1: Replace the entire actions/binding section with speed dial table**

The new `init.lua` should:

1. Keep the same module requires and `banish.start()`.
2. Define the `speedDial` table as a 3x3 grid:

```lua
-- Speed dial grid: rows map to keyboard layout
-- Top:    Q W E  (quirky/app-specific)
-- Middle: A S D  (named layouts)
-- Bottom: Z X C  (generic utilities)
local speedDial = {
  { -- Row 1: Q W E
    { key = "q", label = "IDE+Ghostty", fn = function() orchestrator.ideForGhostty() end },
    { key = "w", label = nil },
    { key = "e", label = nil },
  },
  { -- Row 2: A S D
    { key = "a", label = "Tacitus", fn = function() hs.alert.show("Layout: tacitus"); orchestrator.activateNamedLayout("tacitus") end },
    { key = "s", label = nil },
    { key = "d", label = nil },
  },
  { -- Row 3: Z X C
    { key = "z", label = "Templates", fn = function() orchestrator.showTemplateChooser() end },
    { key = "x", label = "60/40", fn = function() orchestrator.quickSplit() end },
    { key = "c", label = "Tile App", fn = function() orchestrator.tileFrontmostApp() end },
  },
}
```

3. Build the cheat sheet as a 3x3 grid from the table:

```lua
function modal:entered()
  local lines = { "⌃⌘ Speed Dial", "" }
  for _, row in ipairs(speedDial) do
    local cols = {}
    for _, slot in ipairs(row) do
      if slot.label then
        table.insert(cols, string.format("%-2s %-12s", string.upper(slot.key), slot.label))
      else
        table.insert(cols, string.format("%-2s %-12s", string.upper(slot.key), "· · ·"))
      end
    end
    table.insert(lines, table.concat(cols, "  "))
  end
  table.insert(lines, "")
  table.insert(lines, string.format("%-2s %-12s", "R", "Reload"))

  cheatsheet = hs.alert.show(table.concat(lines, "\n"), cheatsheetStyle, hs.screen.mainScreen(), "indefinite")
end
```

4. Bind speed dial keys (both bare and with ctrl+cmd held):

```lua
for _, row in ipairs(speedDial) do
  for _, slot in ipairs(row) do
    if slot.fn then
      local wrapped = function() modal:exit(); slot.fn() end
      modal:bind("", slot.key, wrapped)
      modal:bind({"cmd", "ctrl"}, slot.key, wrapped)
    end
  end
end

-- Keep reload outside the grid
modal:bind("", "r", function() modal:exit(); hs.reload() end)
modal:bind({"cmd", "ctrl"}, "r", function() modal:exit(); hs.reload() end)
modal:bind("", "escape", function() modal:exit() end)
```

5. Keep the hold-to-trigger eventtap, ctrl+cmd+` toggle, global CLI functions, and modalActive state exactly as they are.

**Step 2: Verify manually**

Reload Hammerspoon. Check:
- Cheat sheet shows 3x3 grid
- Q opens IDE chooser
- A triggers tacitus layout
- Z opens template chooser
- X splits the two frontmost windows 60/40
- C tiles all windows of the frontmost app
- C again restores them
- R still reloads
- Unbound slots (W, E, S, D) show as `· · ·` and do nothing

**Step 3: Commit**

```bash
git add hammerspoon/init.lua
git commit -m "feat(hammerspoon): replace modal bindings with 3x3 speed dial grid"
```

---

### Task 5: Verify and clean up

**Step 1: Full manual test**

- Hold ctrl+cmd → cheat sheet appears as grid
- Press each bound key (Q, A, Z, X, C, R)
- Press unbound key (W) → nothing happens, modal stays open
- Press Esc → modal closes
- ctrl+cmd+` toggles modal
- Test tile toggle: open 2+ Ghostty windows, press C, verify tiling, press C again, verify restore

**Step 2: Remove stale templateHotkey references if any remain**

Search for `templateHotkey` in all Hammerspoon files — should be gone after Task 1.

**Step 3: Commit any cleanup**

```bash
git add -A hammerspoon/
git commit -m "chore(hammerspoon): clean up stale references after speed dial refactor"
```
