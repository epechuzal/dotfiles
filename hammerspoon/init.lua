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
  {
    name = "Terminals",
    color = {0.3, 0.6, 1.0},
    cols = 3, x = 0, y = 0,
    keys = {
      { key = "a", label = "Scratch",   fn = function() orchestrator.scratchTerminal() end },
      { key = "s", label = "Worktree",  fn = function() worktree.show() end },
      { key = "d", label = "Exposé",    fn = function() orchestrator.ghosttyExpose() end },
    },
  },
  {
    name = "Apps",
    color = {0.8, 0.5, 1.0},
    cols = 2, x = 0, y = 1,
    keys = {
      { key = "z", label = "Vault",    fn = function() orchestrator.activateNamedLayout("tacitus") end },
      { key = "x", label = "Browser",  fn = function() hs.application.launchOrFocus("Zen") end },
    },
  },
  {
    name = "Find",
    color = {1.0, 0.8, 0.2},
    cols = 1, x = 3, y = 0,
    keys = {
      { key = "f", label = "Finder", fn = function() orchestrator.windowFinder() end },
    },
  },
  {
    name = "Arrange",
    color = {0.3, 0.8, 0.4},
    cols = 2, x = 4, y = 0,
    keys = {
      { key = "h", label = "Templates", fn = function() orchestrator.showTemplateChooser() end },
      { key = "j", label = "Minimize",  fn = function() orchestrator.minimizeAll() end },
      { key = "n", label = "60/40",     fn = function() orchestrator.quickSplit() end },
      { key = "m", label = "Tile",      fn = function() orchestrator.tileFrontmostApp() end },
    },
  },
}

for _, block in ipairs(voyagerDial) do
  for _, slot in ipairs(block.keys) do
    if slot.fn then
      hs.hotkey.bind(hyper, slot.key, slot.fn)
    end
  end
end

local voyagerHelpCanvas = nil

local function showVoyagerHelp()
  if voyagerHelpCanvas then
    voyagerHelpCanvas:delete()
    voyagerHelpCanvas = nil
    return
  end

  local cellW, cellH = 110, 40
  local gap = 8
  local blockGap = 40
  local headerH = 22
  local padding = 30

  -- Calculate bounding box
  local maxX, maxY = 0, 0
  for _, block in ipairs(voyagerDial) do
    local rows = math.ceil(#block.keys / block.cols)
    local bx = block.x * (cellW + blockGap) + block.cols * (cellW + gap)
    local by = block.y * (cellH + blockGap) + headerH + rows * (cellH + gap)
    if bx > maxX then maxX = bx end
    if by > maxY then maxY = by end
  end

  local canvasW = maxX + padding * 2
  local canvasH = maxY + padding * 2
  local screen = hs.screen.mainScreen():frame()
  local cx = screen.x + (screen.w - canvasW) / 2
  local cy = screen.y + (screen.h - canvasH) / 2

  local canvas = hs.canvas.new({ x = cx, y = cy, w = canvasW, h = canvasH })
  canvas:level(hs.canvas.windowLevels.overlay)

  -- Backdrop
  canvas:appendElements({
    type = "rectangle",
    frame = { x = 0, y = 0, w = canvasW, h = canvasH },
    fillColor = { white = 0, alpha = 0.88 },
    strokeWidth = 0,
    roundedRectRadii = { xRadius = 12, yRadius = 12 },
  })

  for _, block in ipairs(voyagerDial) do
    local bx = padding + block.x * (cellW + blockGap)
    local by = padding + block.y * (cellH + blockGap)
    local rows = math.ceil(#block.keys / block.cols)
    local bw = block.cols * cellW + (block.cols - 1) * gap
    local bh = headerH + rows * cellH + (rows - 1) * gap
    local rgb = block.color or {0.5, 0.5, 0.5}

    -- Block border
    canvas:appendElements({
      type = "rectangle",
      frame = { x = bx - 4, y = by - 4, w = bw + 8, h = bh + 8 },
      fillColor = { red = rgb[1], green = rgb[2], blue = rgb[3], alpha = 0.08 },
      strokeColor = { red = rgb[1], green = rgb[2], blue = rgb[3], alpha = 0.3 },
      strokeWidth = 1,
      roundedRectRadii = { xRadius = 8, yRadius = 8 },
    })

    -- Block header
    canvas:appendElements({
      type = "text",
      frame = { x = bx, y = by, w = bw, h = headerH },
      text = hs.styledtext.new(block.name, {
        font = { name = ".AppleSystemUIFont", size = 11 },
        color = { red = rgb[1], green = rgb[2], blue = rgb[3], alpha = 0.7 },
      }),
    })

    -- Keys
    for i, slot in ipairs(block.keys) do
      local col = (i - 1) % block.cols
      local row = math.floor((i - 1) / block.cols)
      local kx = bx + col * (cellW + gap)
      local ky = by + headerH + row * (cellH + gap)

      -- Key background
      canvas:appendElements({
        type = "rectangle",
        frame = { x = kx, y = ky, w = cellW, h = cellH },
        fillColor = { red = rgb[1] * 0.25, green = rgb[2] * 0.25, blue = rgb[3] * 0.25, alpha = 1 },
        strokeColor = { red = rgb[1], green = rgb[2], blue = rgb[3], alpha = 0.5 },
        strokeWidth = 1,
        roundedRectRadii = { xRadius = 6, yRadius = 6 },
      })

      -- Key label
      canvas:appendElements({
        type = "text",
        frame = { x = kx, y = ky + 2, w = cellW, h = cellH - 4 },
        text = hs.styledtext.new(slot.label, {
          font = { name = ".AppleSystemUIFontMonospaced-Regular", size = 14 },
          color = { white = 1, alpha = 0.9 },
          paragraphStyle = { alignment = "center" },
        }),
      })

      -- Key hint (small, bottom-right)
      canvas:appendElements({
        type = "text",
        frame = { x = kx, y = ky + cellH - 16, w = cellW - 5, h = 14 },
        text = hs.styledtext.new(string.upper(slot.key), {
          font = { name = ".AppleSystemUIFont", size = 9 },
          color = { white = 1, alpha = 0.25 },
          paragraphStyle = { alignment = "right" },
        }),
      })
    end
  end

  canvas:show()
  voyagerHelpCanvas = canvas

  -- Safety fallback: dismiss after 15s in case release event is missed
  helpDismissTimer = hs.timer.doAfter(15, function()
    if voyagerHelpCanvas then
      voyagerHelpCanvas:delete()
      voyagerHelpCanvas = nil
    end
  end)
end

local helpDismissTimer = nil
local helpShowTime = nil

hs.hotkey.bind(hyper, "r", function() hs.reload() end)

hs.hotkey.bind(hyper, "p", function()
  -- Show on press
  if not voyagerHelpCanvas then
    showVoyagerHelp()
    helpShowTime = hs.timer.secondsSinceEpoch()
  end
  if helpDismissTimer then helpDismissTimer:stop(); helpDismissTimer = nil end
end, function()
  -- Dismiss on release, but enforce 2s minimum
  local elapsed = helpShowTime and (hs.timer.secondsSinceEpoch() - helpShowTime) or 10
  local function dismiss()
    if voyagerHelpCanvas then
      voyagerHelpCanvas:delete()
      voyagerHelpCanvas = nil
    end
    if helpDismissTimer then helpDismissTimer:stop(); helpDismissTimer = nil end
  end
  if elapsed >= 2 then
    dismiss()
  else
    helpDismissTimer = hs.timer.doAfter(2 - elapsed, dismiss)
  end
end)

-- Load local overrides (machine-specific keybindings, not committed)
local localConfig = hs.configdir .. "/local.lua"
if hs.fs.attributes(localConfig) then
  local ok, err = pcall(dofile, localConfig)
  if not ok then
    clog("local.lua error: " .. tostring(err))
    hs.alert.show("local.lua error — check crash.log")
  end
end

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
