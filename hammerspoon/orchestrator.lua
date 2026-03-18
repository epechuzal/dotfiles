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

-- Build priority map and allow set from preferredApps
local preferredSet = {}
local priorityMap = {}
for i, name in ipairs(layouts.preferredApps or {}) do
  priorityMap[name] = i
  preferredSet[name] = true
end
local defaultPriority = #(layouts.preferredApps or {}) + 1

-- Background cache for Ghostty terminal CWDs (avoids blocking windowFinder)
local ghosttyCwdCache = {}
local function refreshGhosttyCwds()
  local home = os.getenv("HOME") or ""
  local ok, result = hs.osascript.applescript([[
    set output to ""
    tell application "Ghostty"
      repeat with w in (every window)
        set t to focused terminal of selected tab of w
        set tName to name of t
        set tDir to working directory of t
        set output to output & tName & "|" & tDir & linefeed
      end repeat
    end tell
    return output
  ]])
  local cwds = {}
  if ok and result then
    for line in result:gmatch("[^\n]+") do
      local name, cwd = line:match("^(.-)|(.*)")
      if name and cwd and cwd ~= "" then
        if home ~= "" and cwd:sub(1, #home) == home then
          cwd = "~" .. cwd:sub(#home + 1)
        end
        cwds[name] = cwd
      end
    end
  end
  ghosttyCwdCache = cwds
end

-- Only run the timer when Ghostty is actually open
local ghosttyCwdTimer = nil
local ghosttyAppWatcher = hs.application.watcher.new(function(name, event, app)
  if name ~= "Ghostty" then return end
  if event == hs.application.watcher.launched then
    refreshGhosttyCwds()
    if not ghosttyCwdTimer then
      ghosttyCwdTimer = hs.timer.doEvery(5, refreshGhosttyCwds)
    end
  elseif event == hs.application.watcher.terminated then
    if ghosttyCwdTimer then ghosttyCwdTimer:stop(); ghosttyCwdTimer = nil end
    ghosttyCwdCache = {}
  end
end)
ghosttyAppWatcher:start()
if hs.application.get("Ghostty") then
  refreshGhosttyCwds()
  ghosttyCwdTimer = hs.timer.doEvery(5, refreshGhosttyCwds)
end

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
    utils.alert("Unknown layout: " .. name)
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
        utils.alert("No window found: " .. slot.app .. (slot.title and (" / " .. slot.title) or ""))
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
    utils.alert("No Ghostty window found")
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
  utils.showChooser(chooser)
end

function M.quickSplit()
  local front = hs.window.frontmostWindow()
  if not front then
    utils.alert("No frontmost window")
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
      utils.alert("No main app window found")
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
      utils.alert("No Ghostty window found")
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
  utils.showChooser(chooser)
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
  utils.showChooser(chooser)
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
  utils.showChooser(chooser)
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
    utils.alert("No Ghostty windows found")
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
      utils.alert("Couldn't parse working dir from: " .. (choice.text or ""))
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
          utils.alert("WebStorm didn't open in time")
        end
      end
    end)
  end)

  chooser:placeholderText("Open IDE for which project?")
  chooser:choices(choices)
  utils.showChooser(chooser)
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
    utils.alert("No frontmost window")
    return
  end

  local app = frontWin:application()
  local appName = app and app:name() or ""
  local screen = frontWin:screen()
  -- Collect windows of this app on this screen
  local wins = appWindowsOnScreen(appName, screen)
  if #wins == 0 then return end

  -- Unminimize all
  for _, win in ipairs(wins) do
    if win:isMinimized() then win:unminimize() end
  end

  -- Move the current window to the end so it ends up on top
  local frontId = frontWin:id()
  for i, win in ipairs(wins) do
    if win:id() == frontId then
      table.remove(wins, i)
      table.insert(wins, win)
      break
    end
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
    -- 5+: diagonal fan from right to left (top card = current window)
    local winW = math.floor(f.w * 0.4)
    local winH = math.floor(f.h * 0.625)
    local offsetX = math.min(200, math.floor((f.w - winW) / math.max(count - 1, 1)))
    local offsetY = math.min(60, math.floor((f.h - winH) / math.max(count - 1, 1)))
    for i, win in ipairs(wins) do
      win:setFrame({
        x = f.x + f.w - winW - (i - 1) * offsetX,
        y = f.y + (i - 1) * offsetY,
        w = winW,
        h = winH,
      })
    end
  end

  -- Stagger raises so the window server processes them in order
  for i = 1, #wins do
    hs.timer.doAfter(i * 0.04, function()
      wins[i]:raise()
    end)
  end
  hs.timer.doAfter(#wins * 0.04 + 0.05, function()
    wins[#wins]:focus()
  end)
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
    utils.alert("No Ghostty windows found")
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
  utils.showChooser(chooser)
end

-- Ghostty Exposé: fullscreen grid of window thumbnails
function M.ghosttyExpose()
  if M._exposeCanvas then
    M._dismissExpose()
    return
  end

  local ghosttyWindows = utils.findWindows("Ghostty")
  if #ghosttyWindows == 0 then
    utils.alert("No Ghostty windows found")
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
      utils.alert("Scratch terminal didn't open in time")
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

  utils.alert("Hidden " .. count .. " windows")
  log("minimize-all:" .. count)
end

function M.windowFinder()
  local t0 = hs.timer.secondsSinceEpoch()
  local choices = {}
  local iconCache = {}
  local tApps = hs.timer.secondsSinceEpoch()
  local apps = hs.application.runningApplications()
  print(string.format("[finder] runningApplications: %.0fms", (hs.timer.secondsSinceEpoch() - tApps) * 1000))
  for _, app in ipairs(apps) do
    local appName = app:name() or ""
    if hiddenSet[appName] or appName == "" then goto nextapp end
    -- Skip background helper/agent processes (e.g. "Tuple Web Content") — they
    -- hang on allWindows() for ~1.5s and never have useful windows.
    if appName:match("Web Content$") or appName:match("Helper$") then goto nextapp end

    local tApp = hs.timer.secondsSinceEpoch()
    local bundleID = app:bundleID()
    if bundleID and not iconCache[bundleID] then
      iconCache[bundleID] = hs.image.imageFromAppBundle(bundleID)
    end

    local wins = app:allWindows()
    local appMs = (hs.timer.secondsSinceEpoch() - tApp) * 1000
    if appMs > 50 then
      print(string.format("[finder]   slow app: %s %.0fms (%d wins)", appName, appMs, #wins))
    end

    for _, win in ipairs(wins) do
      local title = win:title() or ""
      if title == "" then goto nextwin end

      local subParts = { appName }
      local state = win:isMinimized() and " [min]" or ""

      if appName == "Ghostty" then
        local cwd = ghosttyCwdCache[title]
        if cwd and cwd ~= "" then table.insert(subParts, cwd) end
      end

      table.insert(choices, {
        text = title .. state,
        subText = table.concat(subParts, "  ·  "),
        windowId = win:id(),
        appName = appName,
        image = bundleID and iconCache[bundleID] or nil,
      })

      ::nextwin::
    end
    ::nextapp::
  end

  print(string.format("[finder] window loop: %.0fms (%d choices)", (hs.timer.secondsSinceEpoch() - t0) * 1000, #choices))

  -- Sort: preferred apps first, then alphabetical
  table.sort(choices, function(a, b)
    local pa = priorityMap[a.appName] or defaultPriority
    local pb = priorityMap[b.appName] or defaultPriority
    if pa ~= pb then return pa < pb end
    return a.text < b.text
  end)

  local chooser = hs.chooser.new(function(choice)
    if not choice then return end
    local win = utils.windowById(choice.windowId)
    if win then
      if win:isMinimized() then win:unminimize() end
      win:focus()
      log("finder:" .. (choice.text or "?"))
    end
  end)

  chooser:placeholderText("Find window...")
  chooser:choices(choices)
  print(string.format("[finder] total: %.0fms", (hs.timer.secondsSinceEpoch() - t0) * 1000))
  utils.showChooser(chooser)
end

return M
