hs.ipc.cliInstall()
hs.hotkey.alertDuration = 0

local orchestrator = require("orchestrator")
local layouts = require("layouts")
local banish = require("banish")

-- Start banish watcher
banish.start()

-- Modal: ctrl+cmd activates the mode, then press one key
local modal = hs.hotkey.modal.new({"cmd", "ctrl"}, "\\")

local cheatsheet = nil

function modal:entered()
  local lines = {
    "⌃⌘ + ...",
    "",
    "Space  Template chooser",
    "I      IDE for Ghostty",
    "T      Tacitus layout",
    "R      Reload config",
    "Esc    Cancel",
  }

  -- Add numbered named layouts from config
  local idx = 1
  for name, layout in pairs(layouts.named) do
    if name ~= "tacitus" then
      lines[#lines] = tostring(idx) .. "      " .. name
      table.insert(lines, "Esc    Cancel")
      idx = idx + 1
    end
  end

  cheatsheet = hs.alert.show(table.concat(lines, "\n"), hs.alert.defaultStyle, hs.screen.mainScreen(), "indefinite")
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
