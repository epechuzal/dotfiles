local utils = require("utils")
local layouts = require("layouts")

local M = {}

local logFile = os.getenv("HOME") .. "/.hammerspoon/usage.log"

local function log(entry)
  local f = io.open(logFile, "a")
  if f then
    f:write(os.date("%Y-%m-%d %H:%M") .. "  " .. entry .. "\n")
    f:close()
  end
end

-- Build a set from hiddenApps for fast lookup
local hiddenSet = {}
for _, name in ipairs(layouts.hiddenApps or {}) do
  hiddenSet[name] = true
end

-- Build priority map from preferredApps (lower = higher priority)
local priorityMap = {}
for i, name in ipairs(layouts.preferredApps or {}) do
  priorityMap[name] = i
end
local defaultPriority = #(layouts.preferredApps or {}) + 1

local function sortChoices(choices)
  table.sort(choices, function(a, b)
    local pa = priorityMap[a.appName] or defaultPriority
    local pb = priorityMap[b.appName] or defaultPriority
    if pa ~= pb then return pa < pb end
    return a.text < b.text
  end)
end

function M.activateNamedLayout(name)
  local layout = layouts.named[name]
  if not layout then
    hs.alert.show("Unknown layout: " .. name)
    return
  end

  log("named:" .. name)

  local pendingSlots = {}

  for i, slot in ipairs(layout.slots) do
    local screen = utils.findScreen(slot.screen)

    local matches = utils.findWindows(slot.app, slot.title)

    if #matches == 1 then
      utils.positionWindow(matches[1], slot.position, screen)
      matches[1]:focus()
    elseif #matches == 0 then
      if slot.launch then
        hs.application.launchOrFocus(slot.app)
        hs.timer.doAfter(1, function()
          local wins = utils.findWindows(slot.app, slot.title)
          if #wins > 0 then
            utils.positionWindow(wins[1], slot.position, screen)
          end
        end)
      else
        hs.alert.show("No window found: " .. slot.app .. (slot.title and (" / " .. slot.title) or ""))
      end
    else
      table.insert(pendingSlots, { slot = slot, screen = screen, matches = matches })
    end
  end

  if #pendingSlots > 0 then
    M._resolveAmbiguous(pendingSlots, 1)
  end
end

function M._resolveAmbiguous(pendingSlots, index)
  if index > #pendingSlots then return end

  local pending = pendingSlots[index]
  local slot = pending.slot
  local screen = pending.screen

  local choices = {}
  for _, win in ipairs(pending.matches) do
    table.insert(choices, utils.windowToChoice(win))
  end

  local chooser = hs.chooser.new(function(choice)
    if choice then
      local win = utils.windowById(choice.windowId)
      if win then
        utils.positionWindow(win, slot.position, screen)
        win:focus()
      end
    end
    M._resolveAmbiguous(pendingSlots, index + 1)
  end)

  chooser:placeholderText("Pick window for: " .. slot.app .. (slot.title and (" / " .. slot.title) or ""))
  chooser:choices(choices)
  chooser:show()
end

function M.showTemplateChooser()
  local choices = {}
  for i, tmpl in ipairs(layouts.templates) do
    local slotLabels = {}
    for _, s in ipairs(tmpl.slots) do
      table.insert(slotLabels, s.label)
    end
    table.insert(choices, {
      text = tmpl.name,
      subText = table.concat(slotLabels, " | "),
      templateIndex = i,
    })
  end

  local chooser = hs.chooser.new(function(choice)
    if choice then
      local tmpl = layouts.templates[choice.templateIndex]
      M._fillTemplateSlots(tmpl, {}, 1)
    end
  end)

  chooser:placeholderText("Choose a layout template...")
  chooser:choices(choices)
  chooser:show()
end

function M._fillTemplateSlots(template, assigned, slotIndex)
  if slotIndex > #template.slots then
    local windowNames = {}
    for _, assignment in ipairs(assigned) do
      utils.positionWindow(assignment.window, assignment.position)
      assignment.window:focus()
      local app = assignment.window:application()
      table.insert(windowNames, (app and app:name() or "?") .. ":" .. (assignment.window:title() or "?"))
    end
    if #assigned > 0 then
      assigned[1].window:focus()
    end
    log("template:" .. template.name .. "  windows:" .. table.concat(windowNames, ", "))
    return
  end

  local slot = template.slots[slotIndex]

  local assignedIds = {}
  for _, a in ipairs(assigned) do
    assignedIds[a.window:id()] = true
  end

  local choices = {}
  for _, win in ipairs(hs.window.allWindows()) do
    local title = win:title() or ""
    local app = win:application()
    local appName = app and app:name() or ""
    if title ~= "" and not assignedIds[win:id()] and not hiddenSet[appName] then
      table.insert(choices, utils.windowToChoice(win))
    end
  end
  sortChoices(choices)

  local chooser = hs.chooser.new(function(choice)
    if choice then
      local win = utils.windowById(choice.windowId)
      if win then
        table.insert(assigned, { window = win, position = slot.position })
      end
      M._fillTemplateSlots(template, assigned, slotIndex + 1)
    end
  end)

  chooser:placeholderText("Pick window for: " .. slot.label)
  chooser:choices(choices)
  chooser:show()
end

return M
