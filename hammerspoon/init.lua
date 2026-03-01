hs.ipc.cliInstall()
hs.hotkey.alertDuration = 0

local orchestrator = require("orchestrator")
local layouts = require("layouts")
local banish = require("banish")

-- Bind named layout hotkeys
for name, layout in pairs(layouts.named) do
  if layout.hotkey then
    hs.hotkey.bind(layout.hotkey.mods, layout.hotkey.key, function()
      hs.alert.show("Layout: " .. name)
      orchestrator.activateNamedLayout(name)
    end)
  end
end

-- Bind master template chooser hotkey
hs.hotkey.bind(layouts.templateHotkey.mods, layouts.templateHotkey.key, function()
  orchestrator.showTemplateChooser()
end)

-- Start banish watcher
banish.start()

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

-- Reload config hotkey
hs.hotkey.bind({"cmd", "ctrl"}, "r", function()
  hs.reload()
end)

hs.alert.show("Hammerspoon loaded")
