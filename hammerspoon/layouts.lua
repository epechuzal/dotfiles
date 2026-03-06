local M = {}

M.named = {
  tacitus = {
    slots = {
      { app = "Obsidian", position = {0, 0, 0.6, 1} },
      { app = "Ghostty", title = "tacitus", position = {0.6, 0, 0.4, 1} },
    },
  },
}

M.templates = {
  {
    name = "60/40 Left + Right",
    slots = {
      { label = "Left (60%)", position = {0, 0, 0.6, 1} },
      { label = "Right (40%)", position = {0.6, 0, 0.4, 1} },
    },
  },
  {
    name = "1/2 + 1/2",
    slots = {
      { label = "Left Half", position = {0, 0, 1/2, 1} },
      { label = "Right Half", position = {1/2, 0, 1/2, 1} },
    },
  },
  {
    name = "1/2 Left + 2 Stacked Right",
    slots = {
      { label = "Left Half", position = {0, 0, 1/2, 1} },
      { label = "Top Right", position = {1/2, 0, 1/2, 1/2} },
      { label = "Bottom Right", position = {1/2, 1/2, 1/2, 1/2} },
    },
  },
  {
    name = "Equal Thirds",
    slots = {
      { label = "Left Third", position = {0, 0, 1/3, 1} },
      { label = "Center Third", position = {1/3, 0, 1/3, 1} },
      { label = "Right Third", position = {2/3, 0, 1/3, 1} },
    },
  },
  {
    name = "60 Left + 2 Stacked Right",
    slots = {
      { label = "Left (60%)", position = {0, 0, 0.6, 1} },
      { label = "Top Right (40%)", position = {0.6, 0, 0.4, 0.5} },
      { label = "Bottom Right (40%)", position = {0.6, 0.5, 0.4, 0.5} },
    },
  },
  {
    name = "Full Screen",
    slots = {
      { label = "Full Screen", position = {0, 0, 1, 1} },
    },
  },
}

-- Apps shown first in the window chooser (in this order)
M.preferredApps = { "Zen", "Arc", "Obsidian", "Ghostty", "WebStorm" }

-- Apps never shown in the window chooser
M.hiddenApps = {
  "Hammerspoon", "Notification Center", "Contexts",
  "Surfshark", "Steam", "Steam Helper",
}

-- Ghostty window colors: order = priority in chooser, color = visual tag
-- Colors are {r, g, b} normalized 0-1
M.colorPalette = {
  blue   = {0.13, 0.59, 0.95},  -- #2196F3
  green  = {0.30, 0.69, 0.31},  -- #4CAF50
  amber  = {1.00, 0.60, 0.00},  -- #FF9800
  purple = {0.61, 0.15, 0.69},  -- #9C27B0
  red    = {0.96, 0.26, 0.21},  -- #F44336
  teal   = {0.00, 0.59, 0.53},  -- #009688
  pink   = {0.91, 0.12, 0.39},  -- #E91E63
  gray   = {0.38, 0.49, 0.55},  -- #607D8B
}

M.repoColors = {
  { repo = "scinfax",  color = "blue" },
  { repo = "tacitus",  color = "green" },
  { repo = "dotfiles", color = "amber" },
  { repo = "alfred",   color = "teal" },
  { repo = "journal",  color = "green" },
}

-- Machine-specific overrides (not committed)
-- Create ~/.hammerspoon/local.lua to add/override layouts, preferred/hidden apps
-- Example:
--   return function(layouts)
--     layouts.preferredApps = { "Chrome", "Slack", "Ghostty" }
--     table.insert(layouts.hiddenApps, "Slack")
--     layouts.named.work = {
--       hotkey = { mods = {"cmd", "shift"}, key = "w" },
--       slots = { ... },
--     }
--   end
local ok, localOverrides = pcall(require, "local")
if ok and type(localOverrides) == "function" then
  localOverrides(M)
end

return M
