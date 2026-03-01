hs.ipc.cliInstall()
hs.hotkey.alertDuration = 0

local orchestrator = require("orchestrator")
local layouts = require("layouts")
local banish = require("banish")

-- Start banish watcher
banish.start()

-- Modal: ctrl+cmd+` activates the mode, then press one key
local modal = hs.hotkey.modal.new({"cmd", "ctrl"}, "`")

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

  local lines = { "⌃⌘`  then:", "" }
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

modal:bind("", "space", function()
  modal:exit()
  orchestrator.showTemplateChooser()
end)

modal:bind("", "i", function()
  modal:exit()
  orchestrator.ideForGhostty()
end)

modal:bind("", "t", function()
  modal:exit()
  hs.alert.show("Layout: tacitus")
  orchestrator.activateNamedLayout("tacitus")
end)

modal:bind("", "r", function()
  modal:exit()
  hs.reload()
end)

modal:bind("", "escape", function()
  modal:exit()
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

hs.alert.show("Hammerspoon loaded")
