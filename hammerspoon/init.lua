hs.ipc.cliInstall()
hs.hotkey.alertDuration = 0

local orchestrator = require("orchestrator")
local layouts = require("layouts")
local banish = require("banish")

-- Start banish watcher
banish.start()

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

function modal:entered()
  local entries = {
    { key = "Space", desc = "Template chooser" },
    { key = "I",     desc = "IDE for Ghostty" },
    { key = "T",     desc = "Tacitus layout" },
    { key = "R",     desc = "Reload config" },
    { key = "Esc",   desc = "Cancel" },
  }

  local lines = { "Hold ⌃⌘  then:", "" }
  for _, e in ipairs(entries) do
    table.insert(lines, string.format("  %-7s %s", e.key, e.desc))
  end

  cheatsheet = hs.alert.show(table.concat(lines, "\n"), cheatsheetStyle, hs.screen.mainScreen(), "indefinite")
end

function modal:exited()
  if cheatsheet then
    hs.alert.closeSpecific(cheatsheet)
    cheatsheet = nil
  end
end

-- Bind each action both bare (after release) and with ctrl+cmd held
local actions = {
  { mods = "",               key = "space",  fn = function() modal:exit(); orchestrator.showTemplateChooser() end },
  { mods = {"cmd", "ctrl"},  key = "space",  fn = function() modal:exit(); orchestrator.showTemplateChooser() end },
  { mods = "",               key = "i",      fn = function() modal:exit(); orchestrator.ideForGhostty() end },
  { mods = {"cmd", "ctrl"},  key = "i",      fn = function() modal:exit(); orchestrator.ideForGhostty() end },
  { mods = "",               key = "t",      fn = function() modal:exit(); hs.alert.show("Layout: tacitus"); orchestrator.activateNamedLayout("tacitus") end },
  { mods = {"cmd", "ctrl"},  key = "t",      fn = function() modal:exit(); hs.alert.show("Layout: tacitus"); orchestrator.activateNamedLayout("tacitus") end },
  { mods = "",               key = "r",      fn = function() modal:exit(); hs.reload() end },
  { mods = {"cmd", "ctrl"},  key = "r",      fn = function() modal:exit(); hs.reload() end },
  { mods = "",               key = "escape", fn = function() modal:exit() end },
}

for _, a in ipairs(actions) do
  modal:bind(a.mods, a.key, a.fn)
end

-- Hold ctrl+cmd for 1s to enter modal, release to dismiss if no action taken
local holdTimer = nil
local modalActive = false

local modWatcher = hs.eventtap.new({hs.eventtap.event.types.flagsChanged}, function(event)
  local flags = event:getFlags()
  local ctrlCmd = flags.ctrl and flags.cmd and not flags.alt and not flags.shift

  if ctrlCmd and not modalActive then
    -- Started holding ctrl+cmd, start timer
    if holdTimer then holdTimer:stop() end
    holdTimer = hs.timer.doAfter(0.4, function()
      modalActive = true
      modal:enter()
    end)
  elseif not ctrlCmd then
    -- Released modifiers
    if holdTimer then
      holdTimer:stop()
      holdTimer = nil
    end
    if modalActive then
      -- Give a brief window to press action key after release
      hs.timer.doAfter(1.5, function()
        if modalActive then
          modalActive = false
          modal:exit()
        end
      end)
    end
  end

  return false
end)
modWatcher:start()

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

hs.alert.show("Hammerspoon loaded")
