local M = {}

M.named = {
  tacitus = {
    hotkey = { mods = {"cmd", "shift"}, key = "t" },
    slots = {
      { app = "Obsidian", position = {0, 0, 2/3, 1} },
      { app = "Ghostty", title = "tacitus", position = {2/3, 0, 1/3, 1} },
    },
  },
}

M.templates = {
  {
    name = "2/3 Left + 1/3 Right",
    slots = {
      { label = "Left (2/3)", position = {0, 0, 2/3, 1} },
      { label = "Right (1/3)", position = {2/3, 0, 1/3, 1} },
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
    name = "2/3 Left + 2 Stacked Right",
    slots = {
      { label = "Left (2/3)", position = {0, 0, 2/3, 1} },
      { label = "Top Right (1/3)", position = {2/3, 0, 1/3, 1/2} },
      { label = "Bottom Right (1/3)", position = {2/3, 1/2, 1/3, 1/2} },
    },
  },
  {
    name = "Full Screen",
    slots = {
      { label = "Full Screen", position = {0, 0, 1, 1} },
    },
  },
}

M.templateHotkey = { mods = {"cmd", "ctrl"}, key = "space" }

return M
