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

-- Build priority map and allow set from preferredApps
local preferredSet = {}
local priorityMap = {}
for i, name in ipairs(layouts.preferredApps or {}) do
  priorityMap[name] = i
  preferredSet[name] = true
end
local defaultPriority = #(layouts.preferredApps or {}) + 1

-- Build repo color lookup from layouts config
local repoPriority = {}
local repoColorName = {}
for i, entry in ipairs(layouts.repoColors or {}) do
  repoPriority[entry.repo] = i
  repoColorName[entry.repo] = entry.color
end
local defaultRepoPriority = #(layouts.repoColors or {}) + 1

local SCRATCH_CONF = os.getenv("HOME") .. "/Workspace/dotfiles/ghostty/scratch.conf"

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

local function arrangeQuickSplit(main, terminal)
  local screen = main:screen()
  utils.positionWindow(main, {0, 0, 0.6, 1}, screen)
  utils.positionWindow(terminal, {0.6, 0, 0.4, 1}, screen)
  terminal:focus()
  main:focus()
  local mainName = main:application() and main:application():name() or "?"
  log("quicksplit:" .. mainName .. "+Ghostty")
end

local function pickGhosttyAndArrange(main, ghosttyWins)
  if #ghosttyWins == 0 then
    hs.alert.show("No Ghostty window found")
    return
  end
  if #ghosttyWins == 1 then
    arrangeQuickSplit(main, ghosttyWins[1])
    return
  end
  local choices = {}
  for _, win in ipairs(ghosttyWins) do
    table.insert(choices, utils.windowToChoice(win))
  end
  local chooser = hs.chooser.new(function(choice)
    if choice then
      local win = utils.windowById(choice.windowId)
      if win then arrangeQuickSplit(main, win) end
    end
  end)
  chooser:placeholderText("Pick Ghostty window for right side...")
  chooser:choices(choices)
  chooser:show()
end

function M.quickSplit()
  local front = hs.window.frontmostWindow()
  if not front then
    hs.alert.show("No frontmost window")
    return
  end

  local frontApp = front:application()
  local frontAppName = frontApp and frontApp:name() or ""

  if frontAppName == "Ghostty" then
    -- Frontmost is Ghostty — find most recent preferred app for 60%
    local main = nil
    for _, win in ipairs(hs.window.orderedWindows()) do
      local app = win:application()
      local appName = app and app:name() or ""
      if appName ~= "Ghostty" and preferredSet[appName] and (win:title() or "") ~= "" then
        main = win
        break
      end
    end
    if not main then
      hs.alert.show("No main app window found")
      return
    end
    arrangeQuickSplit(main, front)

  elseif frontAppName == "Obsidian" then
    -- Obsidian → tacitus (Obsidian + Ghostty matching "tacitus")
    M.activateNamedLayout("tacitus")

  elseif frontAppName == "WebStorm" then
    -- WebStorm → match Ghostty by project name (title = "repo: branch")
    local project = front:title() or ""
    local matched = nil
    local allGhostty = utils.findWindows("Ghostty")
    for _, win in ipairs(allGhostty) do
      local title = win:title() or ""
      if title:match("^" .. project .. ":") then
        matched = win
        break
      end
    end
    if matched then
      arrangeQuickSplit(front, matched)
    elseif #allGhostty > 0 then
      pickGhosttyAndArrange(front, allGhostty)
    else
      hs.alert.show("No Ghostty window found")
    end

  else
    -- Browser or other preferred app → chooser if multiple Ghosttys
    local allGhostty = utils.findWindows("Ghostty")
    pickGhosttyAndArrange(front, allGhostty)
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
    -- 5+: diagonal fan (like fanning a deck of cards)
    local winW = math.floor(f.w * 0.4)
    local winH = math.floor(f.h * 0.625)
    local offsetX = math.min(200, math.floor((f.w - winW) / math.max(count - 1, 1)))
    local offsetY = math.min(60, math.floor((f.h - winH) / math.max(count - 1, 1)))
    for i, win in ipairs(wins) do
      win:setFrame({
        x = f.x + (i - 1) * offsetX,
        y = f.y + (i - 1) * offsetY,
        w = winW,
        h = winH,
      })
    end
  end

  -- Raise all windows above other apps: focus in reverse so wins[1] ends on top
  for i = #wins, 1, -1 do
    wins[i]:raise()
  end
  wins[1]:focus()
  log("tile:" .. appName .. " (" .. count .. " windows)")
end

-- Snapshot cache for minimized windows (keyed by window ID)
local snapshotCache = {}

-- Colored circle image for Ghostty window switcher
local colorImageCache = {}

local function colorCircleImage(rgb, alpha)
  alpha = alpha or 1.0
  local key = string.format("%.2f,%.2f,%.2f,%.2f", rgb[1], rgb[2], rgb[3], alpha)
  if colorImageCache[key] then return colorImageCache[key] end

  local size = 24
  local canvas = hs.canvas.new({x = 0, y = 0, w = size, h = size})
  canvas:appendElements({
    type = "circle",
    center = {x = size/2, y = size/2},
    radius = size/2 - 1,
    fillColor = {red = rgb[1], green = rgb[2], blue = rgb[3], alpha = alpha},
    strokeWidth = 0,
  })
  local img = canvas:imageFromCanvas()
  canvas:delete()
  colorImageCache[key] = img
  return img
end

local function ghosttyChoiceImage(title)
  local repo = title:match("^([^:]+):")
  if not repo then
    local rgb = (layouts.colorPalette or {}).gray or {0.38, 0.49, 0.55}
    return colorCircleImage(rgb, 0.5)
  end
  repo = repo:match("^%s*(.-)%s*$")  -- trim

  local colorName = repoColorName[repo] or "gray"
  local rgb = (layouts.colorPalette or {})[colorName] or {0.38, 0.49, 0.55}

  local worktree = title:match(":%s*(.+)$")
  if worktree then
    worktree = worktree:match("^%s*(.-)%s*$")
  end

  if not worktree or worktree == "main" then
    return colorCircleImage(rgb)
  end

  -- Deterministic shade: hash worktree name to pick alpha 0.5-0.85
  local hash = 0
  for i = 1, #worktree do
    hash = (hash * 31 + string.byte(worktree, i)) % 2147483647
  end
  local shade = (hash % 4)  -- 0-3
  local alpha = 0.5 + shade * 0.1167  -- 0.5, 0.617, 0.733, 0.85
  return colorCircleImage(rgb, alpha)
end

function M.ghosttyWindowSwitcher()
  local projectsDir = os.getenv("PROJECTS") or (os.getenv("HOME") .. "/Workspace")
  local ghosttyWindows = utils.findWindows("Ghostty")

  if #ghosttyWindows == 0 then
    hs.alert.show("No Ghostty windows found")
    return
  end

  local choices = {}
  for _, win in ipairs(ghosttyWindows) do
    local title = win:title() or ""
    local repo = title:match("^([^:]+):")
    if repo then repo = repo:match("^%s*(.-)%s*$") end

    local frame = win:frame()
    local dims = string.format("%d×%d", frame.w, frame.h)
    local path = repo and (projectsDir .. "/" .. repo) or "scratch / other"
    local state = win:isMinimized() and "  [min]" or win:isFullScreen() and "  [full]" or ""

    table.insert(choices, {
      text = title,
      subText = path .. "  ·  " .. dims .. state,
      windowId = win:id(),
      _repo = repo,
      image = ghosttyChoiceImage(title),
    })
  end

  table.sort(choices, function(a, b)
    local pa = repoPriority[a._repo] or defaultRepoPriority
    local pb = repoPriority[b._repo] or defaultRepoPriority
    if pa ~= pb then return pa < pb end
    return a.text < b.text
  end)

  local chooser = hs.chooser.new(function(choice)
    if not choice then return end
    local win = utils.windowById(choice.windowId)
    if win then
      log("ghostty-switch:" .. (choice.text or "?"))
      win:focus()
    end
  end)

  chooser:placeholderText("Switch to Ghostty window...")
  chooser:choices(choices)
  chooser:show()
end

-- Ghostty Exposé: fullscreen grid of window thumbnails
function M.ghosttyExpose()
  if M._exposeCanvas then
    M._dismissExpose()
    return
  end

  local ghosttyWindows = utils.findWindows("Ghostty")
  if #ghosttyWindows == 0 then
    hs.alert.show("No Ghostty windows found")
    return
  end

  -- Sort by repo priority (same order as chooser)
  table.sort(ghosttyWindows, function(a, b)
    local repoA = (a:title() or ""):match("^([^:]+):")
    local repoB = (b:title() or ""):match("^([^:]+):")
    if repoA then repoA = repoA:match("^%s*(.-)%s*$") end
    if repoB then repoB = repoB:match("^%s*(.-)%s*$") end
    local pa = repoPriority[repoA] or defaultRepoPriority
    local pb = repoPriority[repoB] or defaultRepoPriority
    if pa ~= pb then return pa < pb end
    return (a:title() or "") < (b:title() or "")
  end)

  local screen = hs.screen.mainScreen()
  local sf = screen:fullFrame()
  local count = math.min(#ghosttyWindows, 9)

  -- Grid dimensions
  local cols = count <= 3 and count or (count <= 4 and 2 or 3)
  local rows = math.ceil(count / cols)

  -- Card sizing
  local padding = 30
  local gap = 20
  local labelH = 38
  local maxCardW = 900
  local cardW = math.min(maxCardW, (sf.w - padding * 2 - gap * (cols - 1)) / cols)
  local thumbH = cardW / 3
  local cardH = thumbH + labelH

  local totalW = cols * cardW + (cols - 1) * gap
  local totalH = rows * cardH + (rows - 1) * gap
  local baseX = (sf.w - totalW) / 2
  local baseY = (sf.h - totalH) / 2

  -- Batch-gather cwd + foreground process for each Ghostty PID
  -- Process tree: ghostty → login → zsh → foreground process
  local procInfo = {} -- pid → { cwd = "...", proc = "..." }
  local psOutput, _ = hs.execute(
    "for pid in $(pgrep -x ghostty); do "
    .. "login=$(pgrep -P $pid | head -1); "
    .. "[ -z \"$login\" ] && continue; "
    .. "shell=$(pgrep -P $login | head -1); "
    .. "[ -z \"$shell\" ] && continue; "
    .. "cwd=$(lsof -a -d cwd -Fn -p $shell 2>/dev/null | grep ^n | head -1 | cut -c2-); "
    .. "fg=$(pgrep -P $shell | tail -1); "
    .. "if [ -n \"$fg\" ]; then proc=$(ps -o comm= -p $fg 2>/dev/null); "
    .. "else proc=$(ps -o comm= -p $shell 2>/dev/null); fi; "
    .. "echo \"$pid|$cwd|$proc\"; "
    .. "done"
  )
  if psOutput then
    for line in psOutput:gmatch("[^\n]+") do
      local pid, cwd, proc = line:match("^(%d+)|(.-)|(.*)")
      if pid then
        local home = os.getenv("HOME") or ""
        if cwd and home ~= "" and cwd:sub(1, #home) == home then
          cwd = "~" .. cwd:sub(#home + 1)
        end
        procInfo[tonumber(pid)] = { cwd = cwd or "", proc = proc or "" }
      end
    end
  end

  local canvas = hs.canvas.new(sf)
  canvas:level(hs.canvas.windowLevels.overlay)

  local elCount = 0
  local borderMap = {}   -- card number → element index
  local cardLookup = {} -- element index → card number
  local windowByCard = {}

  -- Backdrop
  canvas:appendElements({
    type = "rectangle",
    frame = { x = 0, y = 0, w = sf.w, h = sf.h },
    fillColor = { white = 0, alpha = 0.75 },
    strokeWidth = 0,
    trackMouseUp = true,
    id = "backdrop",
  })
  elCount = elCount + 1

  for i = 1, count do
    local win = ghosttyWindows[i]
    windowByCard[i] = win
    local r = math.floor((i - 1) / cols)
    local c = (i - 1) % cols
    local x = baseX + c * (cardW + gap)
    local y = baseY + r * (cardH + gap)
    local title = win:title() or ""
    local repo = title:match("^([^:]+):")
    if repo then repo = repo:match("^%s*(.-)%s*$") end

    -- Card background/border
    canvas:appendElements({
      type = "rectangle",
      frame = { x = x, y = y, w = cardW, h = cardH },
      fillColor = { white = 0.1, alpha = 0.95 },
      strokeColor = { white = 0.3, alpha = 0.5 },
      strokeWidth = 2,
      roundedRectRadii = { xRadius = 10, yRadius = 10 },
    })
    elCount = elCount + 1
    borderMap[i] = elCount

    -- Thumbnail: crop to bottom 25% of window (last few lines of output)
    local snapshot = win:snapshot() or snapshotCache[win:id()]
    if snapshot then
      local imgSize = snapshot:size()
      -- Crop a bottom-left rectangle sized to display at 1:1 text scale
      local winFrame = win:frame()
      local scale = winFrame.w > 0 and (imgSize.w / winFrame.w) or 2
      local cropW = math.min(cardW * scale, imgSize.w)
      local cropH = math.min(thumbH * scale, imgSize.h)
      local bottomPad = 20 * scale -- skip rounded corner area
      local cropped = snapshot:croppedCopy({
        x = 0,
        y = math.max(0, imgSize.h - cropH - bottomPad),
        w = cropW,
        h = cropH,
      })
      canvas:appendElements({
        type = "image",
        frame = { x = x + 4, y = y + 4, w = cardW - 8, h = thumbH - 8 },
        image = cropped or snapshot,
        imageScaling = "scaleToFit",
      })
    else
      canvas:appendElements({
        type = "text",
        frame = { x = x + 4, y = y + thumbH / 2 - 12, w = cardW - 8, h = 24 },
        text = hs.styledtext.new("minimized", {
          font = { name = ".AppleSystemUIFont", size = 14 },
          color = { white = 0.4 },
          paragraphStyle = { alignment = "center" },
        }),
      })
    end
    elCount = elCount + 1

    -- Colored dot
    local colorName = repoColorName[repo] or "gray"
    local rgb = (layouts.colorPalette or {})[colorName] or {0.38, 0.49, 0.55}
    canvas:appendElements({
      type = "circle",
      center = { x = x + 18, y = y + thumbH + labelH / 2 },
      radius = 6,
      fillColor = { red = rgb[1], green = rgb[2], blue = rgb[3], alpha = 1 },
      strokeWidth = 0,
      action = "fill",
    })
    elCount = elCount + 1

    -- Label: title + cwd/process
    local info = procInfo[win:application() and win:application():pid() or 0]
    local line2 = ""
    if info then
      local parts = {}
      if info.cwd ~= "" then table.insert(parts, info.cwd) end
      if info.proc ~= "" then table.insert(parts, info.proc) end
      line2 = table.concat(parts, "  ·  ")
    end
    local labelText = hs.styledtext.new(title .. "\n", {
      font = { name = ".AppleSystemUIFontMonospaced-Regular", size = 13 },
      color = { white = 1, alpha = 0.9 },
    }) .. hs.styledtext.new(line2, {
      font = { name = ".AppleSystemUIFontMonospaced-Regular", size = 11 },
      color = { white = 1, alpha = 0.5 },
    })
    canvas:appendElements({
      type = "text",
      frame = { x = x + 32, y = y + thumbH + 2, w = cardW - 72, h = labelH - 4 },
      text = labelText,
    })
    elCount = elCount + 1

    -- Number badge
    canvas:appendElements({
      type = "text",
      frame = { x = x + cardW - 36, y = y + thumbH + 4, w = 28, h = labelH - 8 },
      text = hs.styledtext.new(tostring(i), {
        font = { name = ".AppleSystemUIFontMonospaced-Regular", size = 14 },
        color = { white = 1, alpha = 0.35 },
        paragraphStyle = { alignment = "right" },
      }),
    })
    elCount = elCount + 1

    -- Interaction overlay (transparent hit area for hover + click)
    canvas:appendElements({
      type = "rectangle",
      frame = { x = x, y = y, w = cardW, h = cardH },
      fillColor = { white = 0, alpha = 0 },
      strokeWidth = 0,
      roundedRectRadii = { xRadius = 10, yRadius = 10 },
      trackMouseEnterExit = true,
      trackMouseUp = true,
      id = "card_" .. i,
    })
    elCount = elCount + 1
    cardLookup[elCount] = i
  end

  -- Mouse callback
  canvas:mouseCallback(function(c, msg, id, x, y)
    local cardNum = nil
    if type(id) == "string" then
      cardNum = tonumber(id:match("card_(%d+)"))
    elseif type(id) == "number" then
      cardNum = cardLookup[id]
    end

    if msg == "mouseEnter" and cardNum and borderMap[cardNum] then
      c:elementAttribute(borderMap[cardNum], "strokeColor", { white = 1, alpha = 0.9 })
      c:elementAttribute(borderMap[cardNum], "strokeWidth", 3)
    elseif msg == "mouseExit" and cardNum and borderMap[cardNum] then
      c:elementAttribute(borderMap[cardNum], "strokeColor", { white = 0.3, alpha = 0.5 })
      c:elementAttribute(borderMap[cardNum], "strokeWidth", 2)
    elseif msg == "mouseUp" then
      if cardNum and windowByCard[cardNum] then
        local win = windowByCard[cardNum]
        M._dismissExpose()
        win:focus()
        log("ghostty-expose:" .. (win:title() or "?"))
      else
        M._dismissExpose()
      end
    end
  end)

  -- Keyboard handler
  local keyTap = hs.eventtap.new({hs.eventtap.event.types.keyDown}, function(event)
    local keyCode = event:getKeyCode()
    local key = event:getCharacters()

    if keyCode == 53 then -- escape
      M._dismissExpose()
      return true
    end

    local num = tonumber(key)
    if num and num >= 1 and num <= count and windowByCard[num] then
      local win = windowByCard[num]
      M._dismissExpose()
      win:focus()
      log("ghostty-expose:" .. (win:title() or "?"))
      return true
    end

    return true -- consume all keys while expose is open
  end)

  M._exposeCanvas = canvas
  M._exposeKeyTap = keyTap
  keyTap:start()
  canvas:show()
end

function M._dismissExpose()
  if M._exposeCanvas then
    M._exposeCanvas:delete()
    M._exposeCanvas = nil
  end
  if M._exposeKeyTap then
    M._exposeKeyTap:stop()
    M._exposeKeyTap = nil
  end
end

local scratchLaunching = false

function M.scratchTerminal()
  -- Find existing scratch Ghostty by grepping process args for scratch.conf
  local output, status = hs.execute("ps -eo pid,args | grep '[G]hostty.app/Contents/MacOS/ghostty' | grep '" .. SCRATCH_CONF .. "' | awk '{print $1}' | head -1")
  local pid = output and tonumber(output:match("%d+"))

  if pid then
    -- Find the window for this PID and focus it
    for _, app in ipairs(hs.application.runningApplications()) do
      if app:name() == "Ghostty" and app:pid() == pid then
        local wins = app:allWindows()
        if #wins > 0 then
          wins[1]:focus()
          log("scratch:focus")
          return
        end
      end
    end
  end

  if scratchLaunching then return end
  scratchLaunching = true

  -- Launch new scratch terminal
  hs.task.new("/usr/bin/open", nil, {
    "-na", "Ghostty.app", "--args",
    "--config-file=" .. SCRATCH_CONF,
    "--working-directory=" .. os.getenv("HOME"),
    "-e", "zsh", "-l",
  }):start()

  -- Poll for window, then position 1400x900 centered
  local attempts = 0
  hs.timer.doEvery(0.2, function(timer)
    attempts = attempts + 1
    for _, app in ipairs(hs.application.runningApplications()) do
      if app:name() == "Ghostty" then
        -- Check if this is the scratch process by inspecting its args
        local check, _ = hs.execute("ps -o args= -p " .. tostring(app:pid()))
        if check and check:find(SCRATCH_CONF, 1, true) then
          local wins = app:allWindows()
          if #wins > 0 then
            timer:stop()
            scratchLaunching = false
            local screen = hs.screen.mainScreen():frame()
            local w, h = 1400, 900
            wins[1]:setFrame({
              x = screen.x + (screen.w - w) / 2,
              y = screen.y + (screen.h - h) / 2,
              w = w,
              h = h,
            })
            wins[1]:focus()
            log("scratch:create")
            return
          end
        end
      end
    end
    if attempts > 25 then
      timer:stop()
      scratchLaunching = false
      hs.alert.show("Scratch terminal didn't open in time")
    end
  end)
end

-- Center a Ghostty window by title prefix (called from Alfred via hs CLI)
-- Polls until the window appears, then centers it at 1400x900
function M.centerGhosttyWindow(titlePrefix)
  local attempts = 0
  hs.timer.doEvery(0.3, function(timer)
    attempts = attempts + 1
    local wins = utils.findWindows("Ghostty", "^" .. titlePrefix)
    if #wins > 0 then
      timer:stop()
      local screen = hs.screen.mainScreen():frame()
      local w, h = 1400, 900
      wins[1]:setFrame({
        x = screen.x + (screen.w - w) / 2,
        y = screen.y + (screen.h - h) / 2,
        w = w,
        h = h,
      })
      log("wt-center:" .. titlePrefix)
    elseif attempts > 20 then
      timer:stop()
    end
  end)
end

function M.minimizeAll()
  local keepSet = {}
  for _, name in ipairs(layouts.preferredApps or {}) do
    if name ~= "Ghostty" then
      keepSet[name] = true
    end
  end
  -- Always keep Hammerspoon itself
  keepSet["Hammerspoon"] = true

  -- Cache snapshots of visible windows before hiding (exposé needs them)
  for _, win in ipairs(hs.window.allWindows()) do
    if not win:isMinimized() then
      local snap = win:snapshot()
      if snap then snapshotCache[win:id()] = snap end
    end
  end

  -- Hide apps (not minimize) — dimmed dock icon, no thumbnail clutter
  local count = 0
  for _, app in ipairs(hs.application.runningApplications()) do
    local appName = app:name() or ""
    if not keepSet[appName] and not app:isHidden() then
      local visibleCount = #app:visibleWindows()
      app:hide()
      count = count + visibleCount
    end
  end

  hs.alert.show("Hidden " .. count .. " windows")
  log("minimize-all:" .. count)
end

return M
