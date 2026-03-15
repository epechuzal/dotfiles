hs.ipc.cliInstall()
hs.hotkey.alertDuration = 0

-- Persistent log for debugging crashes (survives restarts)
local crashLog = os.getenv("HOME") .. "/.hammerspoon/crash.log"
local function clog(msg)
  local f = io.open(crashLog, "a")
  if f then
    f:write(os.date("%Y-%m-%d %H:%M:%S") .. "  " .. msg .. "\n")
    f:close()
  end
end
clog("=== Hammerspoon loaded ===")

local orchestrator = require("orchestrator")
local layouts = require("layouts")
local banish = require("banish")
local worktree = require("worktree")

-- Start banish watcher
banish.start()

-- Auto-reload on config changes (watch real source dir, not symlinks)
local configSourceDir = hs.execute("readlink " .. hs.configdir .. "/init.lua"):match("(.+)/[^/]+$")
clog("watching: " .. (configSourceDir or hs.configdir))
local configWatcher = hs.pathwatcher.new(configSourceDir or hs.configdir, function(files)
  for _, f in ipairs(files) do
    if f:match("%.lua$") then
      clog("config changed: " .. f .. " — reloading")
      hs.reload()
      return
    end
  end
end)
configWatcher:start()

-- Modal with cheat sheet
local modal = hs.hotkey.modal.new()

local cheatsheet = nil

local cheatsheetStyle = {
  strokeWidth = 0,
  strokeColor = { white = 0, alpha = 0 },
  fillColor = { white = 0, alpha = 0.85 },
  textColor = { white = 1, alpha = 1 },
  textFont = ".AppleSystemUIFontMonospaced-Regular",
  textSize = 16,
  radius = 12,
  atScreenEdge = 0,
  padding = 24,
}

-- Speed dial grid: rows map to keyboard layout
-- Top:    Q W E  (quirky/app-specific)
-- Middle: A S D  (named layouts)
-- Bottom: Z X C  (generic utilities)
local speedDial = {
  { -- Row 1: Q W E
    { key = "q", label = "IDE+Ghostty", fn = function() orchestrator.ideForGhostty() end },
    { key = "w", label = "Worktree", fn = function() worktree.show() end },
    { key = "e", label = "Scratch", fn = function() orchestrator.scratchTerminal() end },
  },
  { -- Row 2: A S D
    { key = "a", label = "Tacitus", fn = function() hs.alert.show("Layout: tacitus"); orchestrator.activateNamedLayout("tacitus") end },
    { key = "s", label = "Zen", fn = function() hs.application.launchOrFocus("Zen") end },
    { key = "d", label = "Exposé", fn = function() orchestrator.ghosttyExpose() end },
  },
  { -- Row 3: Z X C
    { key = "z", label = "Templates", fn = function() orchestrator.showTemplateChooser() end },
    { key = "x", label = "60/40", fn = function() orchestrator.quickSplit() end },
    { key = "c", label = "Tile App", fn = function() orchestrator.tileFrontmostApp() end },
  },
}

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
  table.insert(lines, string.format("%-2s %-12s  %-2s %-12s", "M", "Minimize All", "R", "Reload"))

  cheatsheet = hs.alert.show(table.concat(lines, "\n"), cheatsheetStyle, hs.screen.mainScreen(), "indefinite")
end

function modal:exited()
  if cheatsheet then
    hs.alert.closeSpecific(cheatsheet)
    cheatsheet = nil
  end
end

for _, row in ipairs(speedDial) do
  for _, slot in ipairs(row) do
    if slot.fn then
      local wrapped = function() modal:exit(); slot.fn() end
      modal:bind("", slot.key, wrapped)
      modal:bind({"cmd", "ctrl"}, slot.key, wrapped)
    end
  end
end

-- Extra keys outside the grid
modal:bind("", "m", function() modal:exit(); orchestrator.minimizeAll() end)
modal:bind({"cmd", "ctrl"}, "m", function() modal:exit(); orchestrator.minimizeAll() end)
modal:bind("", "r", function() modal:exit(); hs.reload() end)
modal:bind({"cmd", "ctrl"}, "r", function() modal:exit(); hs.reload() end)
modal:bind("", "escape", function() modal:exit() end)

-- Hold ctrl+cmd for 1s to enter modal, release to dismiss if no action taken
local holdTimer = nil
local modalActive = false

local lastEventTapHeartbeat = hs.timer.secondsSinceEpoch()

local function createModWatcher()
  return hs.eventtap.new({hs.eventtap.event.types.flagsChanged}, function(event)
    lastEventTapHeartbeat = hs.timer.secondsSinceEpoch()
    local ok, err = pcall(function()
      local flags = event:getFlags()
      local ctrlCmd = flags.ctrl and flags.cmd and not flags.alt and not flags.shift

      if ctrlCmd and not modalActive then
        if holdTimer then holdTimer:stop() end
        holdTimer = hs.timer.doAfter(0.15, function()
          modalActive = true
          modal:enter()
        end)
      elseif not ctrlCmd then
        if holdTimer then
          holdTimer:stop()
          holdTimer = nil
        end
        if modalActive then
          hs.timer.doAfter(1.5, function()
            if modalActive then
              modalActive = false
              modal:exit()
            end
          end)
        end
      end
    end)
    if not ok then
      clog("modWatcher error: " .. tostring(err))
    end
    return false
  end)
end

local modWatcher = createModWatcher()
modWatcher:start()

-- Heartbeat watchdog: if no modifier key events in 120s, recreate the eventtap
-- (isEnabled() can lie — macOS may drop the event stream silently)
hs.timer.doEvery(30, function()
  local elapsed = hs.timer.secondsSinceEpoch() - lastEventTapHeartbeat
  if not modWatcher:isEnabled() or elapsed > 120 then
    clog("watchdog: restarting eventtap (enabled=" .. tostring(modWatcher:isEnabled()) .. " elapsed=" .. string.format("%.0f", elapsed) .. "s)")
    modWatcher:stop()
    modWatcher = createModWatcher()
    modWatcher:start()
    lastEventTapHeartbeat = hs.timer.secondsSinceEpoch()
  end
end)

-- Also support ctrl+cmd+` as direct trigger (no hold delay)
hs.hotkey.bind({"cmd", "ctrl"}, "`", function()
  if modalActive then
    modalActive = false
    modal:exit()
  else
    modalActive = true
    modal:enter()
  end
end)

-- Reset modal state when actions complete
local origExit = modal.exited
function modal:exited()
  modalActive = false
  origExit(self)
end

-- Voyager speed dial: Hyper (ctrl+cmd+alt+shift) + key = direct action, no modal
local hyper = {"ctrl", "cmd", "alt", "shift"}

local voyagerDial = {
  { key = "w", label = "Worktree", fn = function() worktree.show() end },
  { key = "g", label = "Ghostty", fn = function() orchestrator.ghosttyExpose() end },
  { key = "t", label = "Terminal", fn = function() orchestrator.scratchTerminal() end },
  { key = "b", label = "Browser", fn = function() hs.application.launchOrFocus("Zen") end },
  { key = "v", label = "Vault", fn = function() orchestrator.activateNamedLayout("tacitus") end },
  { key = "n", label = "Templates", fn = function() orchestrator.showTemplateChooser() end },
  { key = "m", label = "Minimize", fn = function() orchestrator.minimizeAll() end },
  { key = "x", label = "60/40", fn = function() orchestrator.quickSplit() end },
  { key = "c", label = "Tile", fn = function() orchestrator.tileFrontmostApp() end },
}

for _, slot in ipairs(voyagerDial) do
  hs.hotkey.bind(hyper, slot.key, slot.fn)
end

hs.hotkey.bind(hyper, "h", function()
  local lines = { "Voyager Speed Dial", "" }
  for _, slot in ipairs(voyagerDial) do
    table.insert(lines, string.format("%-2s  %s", string.upper(slot.key), slot.label))
  end
  table.insert(lines, "")
  table.insert(lines, "H   Help")
  hs.alert.show(table.concat(lines, "\n"), cheatsheetStyle, hs.screen.mainScreen(), 5)
end)

-- Global functions for CLI access (hs -c "...")
function activateNamedLayout(name)
  orchestrator.activateNamedLayout(name)
end

function activateTemplate(name)
  for i, tmpl in ipairs(layouts.templates) do
    if tmpl.name == name then
      orchestrator._fillTemplateSlots(tmpl, {}, 1)
      return
    end
  end
  hs.alert.show("Unknown template: " .. name)
end

function openIDE()
  orchestrator.ideForGhostty()
end

function showWorktree()
  worktree.show()
end

hs.alert.show("Hammerspoon loaded")
