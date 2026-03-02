local utils = require("utils")
local layouts = require("layouts")

local M = {}

local logFile = os.getenv("HOME") .. "/.hammerspoon/usage.log"

-- Tile toggle snapshot: keyed by "appName:screenId"
local tileSnapshots = {}

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

function M.quickSplit()
  local wins = hs.window.orderedWindows()
  if #wins < 2 then
    hs.alert.show("Need at least 2 windows")
    return
  end

  local first = wins[1]
  local second = wins[2]
  local screen = first:screen()

  utils.positionWindow(first, {0, 0, 0.6, 1}, screen)
  utils.positionWindow(second, {0.6, 0, 0.4, 1}, screen)
  first:focus()

  local firstName = first:application() and first:application():name() or "?"
  local secondName = second:application() and second:application():name() or "?"
  log("quicksplit:" .. firstName .. "+" .. secondName)
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

-- "Open IDE alongside Ghostty" flow:
-- Shows all Ghostty windows, user picks one, derives working dir from
-- title ("repo: branch" → ~/Workspace/repo), launches WebStorm there,
-- arranges WebStorm 60% left + Ghostty 40% right.
function M.ideForGhostty()
  local projectsDir = os.getenv("PROJECTS") or (os.getenv("HOME") .. "/Workspace")

  -- Collect all Ghostty windows across all instances
  local ghosttyWindows = {}
  for _, app in ipairs(hs.application.runningApplications()) do
    if app:name() == "Ghostty" then
      for _, win in ipairs(app:allWindows()) do
        local title = win:title() or ""
        if title ~= "" then
          table.insert(ghosttyWindows, win)
        end
      end
    end
  end

  if #ghosttyWindows == 0 then
    hs.alert.show("No Ghostty windows found")
    return
  end

  local choices = {}
  for _, win in ipairs(ghosttyWindows) do
    local title = win:title() or ""
    -- Parse "repo: branch" → repo
    local repo = title:match("^([^:]+):")
    table.insert(choices, {
      text = title,
      subText = repo and (projectsDir .. "/" .. repo) or "unknown dir",
      windowId = win:id(),
      repo = repo,
      image = hs.image.imageFromAppBundle("com.mitchellh.ghostty"),
    })
  end

  local chooser = hs.chooser.new(function(choice)
    if not choice then return end

    local ghosttyWin = utils.windowById(choice.windowId)
    if not ghosttyWin then return end

    local dir = choice.repo and (projectsDir .. "/" .. choice.repo) or nil
    if not dir then
      hs.alert.show("Couldn't parse working dir from: " .. (choice.text or ""))
      return
    end

    log("ide:" .. choice.text .. "  dir:" .. dir)

    local function arrange(wsWin)
      utils.positionWindow(wsWin, {0, 0, 0.6, 1})
      utils.positionWindow(ghosttyWin, {0.6, 0, 0.4, 1})
      wsWin:focus()
      ghosttyWin:focus()
    end

    -- Check if WebStorm already has this project open
    local existing = utils.findWindows("WebStorm", choice.repo)
    if #existing > 0 then
      arrange(existing[1])
      return
    end

    -- Not open yet — launch and poll for window
    hs.task.new("/opt/homebrew/bin/webstorm", nil, {dir}):start()

    local attempts = 0
    hs.timer.doEvery(0.5, function(timer)
      attempts = attempts + 1
      local wsWins = utils.findWindows("WebStorm", choice.repo)
      if #wsWins > 0 then
        timer:stop()
        arrange(wsWins[1])
      elseif attempts > 20 then
        timer:stop()
        local allWs = utils.findWindows("WebStorm")
        if #allWs > 0 then
          arrange(allWs[1])
        else
          hs.alert.show("WebStorm didn't open in time")
        end
      end
    end)
  end)

  chooser:placeholderText("Open IDE for which project?")
  chooser:choices(choices)
  chooser:show()
end

local function appWindowsOnScreen(appName, screen)
  local wins = {}
  for _, app in ipairs(hs.application.runningApplications()) do
    if app:name() == appName then
      for _, win in ipairs(app:allWindows()) do
        local title = win:title() or ""
        local winScreen = win:screen()
        if title ~= "" and winScreen and winScreen:id() == screen:id() then
          table.insert(wins, win)
        end
      end
    end
  end
  return wins
end

function M.tileFrontmostApp()
  local frontWin = hs.window.frontmostWindow()
  if not frontWin then
    hs.alert.show("No frontmost window")
    return
  end

  local app = frontWin:application()
  local appName = app and app:name() or ""
  local screen = frontWin:screen()
  local snapshotKey = appName .. ":" .. tostring(screen:id())

  -- Collect windows of this app on this screen
  local wins = appWindowsOnScreen(appName, screen)
  if #wins == 0 then return end

  -- Check for toggle: restore if snapshot exists and windows match
  local snap = tileSnapshots[snapshotKey]
  if snap then
    local snapIds = {}
    for _, s in ipairs(snap) do snapIds[s.id] = true end
    local currentIds = {}
    for _, w in ipairs(wins) do currentIds[w:id()] = true end

    -- Check windows haven't changed
    local match = true
    for id in pairs(snapIds) do
      if not currentIds[id] then match = false; break end
    end
    for id in pairs(currentIds) do
      if not snapIds[id] then match = false; break end
    end

    if match then
      -- Restore
      for _, s in ipairs(snap) do
        local win = hs.window.get(s.id)
        if win then
          win:setFrame(s.frame)
          if s.minimized then win:minimize() end
        end
      end
      tileSnapshots[snapshotKey] = nil
      log("tile-restore:" .. appName .. " (" .. #snap .. " windows)")
      return
    else
      -- Windows changed, discard snapshot
      tileSnapshots[snapshotKey] = nil
    end
  end

  -- Save snapshot
  local snapshot = {}
  for _, win in ipairs(wins) do
    table.insert(snapshot, {
      id = win:id(),
      frame = win:frame(),
      minimized = win:isMinimized(),
    })
  end
  tileSnapshots[snapshotKey] = snapshot

  -- Unminimize all
  for _, win in ipairs(wins) do
    if win:isMinimized() then win:unminimize() end
  end

  local f = screen:frame()
  local count = #wins

  if count == 1 then
    utils.positionWindow(wins[1], {0, 0, 1, 1}, screen)
  elseif count == 2 then
    utils.positionWindow(wins[1], {0, 0, 0.5, 1}, screen)
    utils.positionWindow(wins[2], {0.5, 0, 0.5, 1}, screen)
  elseif count == 3 then
    for i, win in ipairs(wins) do
      utils.positionWindow(win, {(i-1)/3, 0, 1/3, 1}, screen)
    end
  elseif count == 4 then
    utils.positionWindow(wins[1], {0, 0, 0.5, 0.5}, screen)
    utils.positionWindow(wins[2], {0.5, 0, 0.5, 0.5}, screen)
    utils.positionWindow(wins[3], {0, 0.5, 0.5, 0.5}, screen)
    utils.positionWindow(wins[4], {0.5, 0.5, 0.5, 0.5}, screen)
  else
    -- 5+: fanned cascade
    local minW = f.w * 0.5
    local offsetX = (f.w - minW) / (count - 1)
    for i, win in ipairs(wins) do
      win:setFrame({
        x = f.x + (i - 1) * offsetX,
        y = f.y,
        w = minW,
        h = f.h,
      })
    end
  end

  -- Focus the first window last so it's on top
  wins[1]:focus()
  log("tile:" .. appName .. " (" .. count .. " windows)")
end

return M
