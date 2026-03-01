local utils = require("utils")
local layouts = require("layouts")

local M = {}

function M.activateNamedLayout(name)
  local layout = layouts.named[name]
  if not layout then
    hs.alert.show("Unknown layout: " .. name)
    return
  end

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
    for _, assignment in ipairs(assigned) do
      utils.positionWindow(assignment.window, assignment.position)
      assignment.window:focus()
    end
    if #assigned > 0 then
      assigned[1].window:focus()
    end
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
    if title ~= "" and not assignedIds[win:id()] then
      table.insert(choices, utils.windowToChoice(win))
    end
  end

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
