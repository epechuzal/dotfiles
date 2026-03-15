local layouts = require("layouts")

local M = {}

local SCRIPT = os.getenv("HOME") .. "/Workspace/dotfiles/hammerspoon/scripts/wt-git.sh"
local WORKSPACE = os.getenv("HOME") .. "/Workspace"

local repoPriority = {}
for i, entry in ipairs(layouts.repoColors) do
  repoPriority[entry.repo] = i
end
local defaultPriority = #layouts.repoColors + 1

local function runGit(...)
  local args = table.concat({...}, " ")
  local output, status = hs.execute(SCRIPT .. " " .. args)
  if not status then
    hs.alert.show("wt-git.sh failed")
    return nil
  end
  local ok, result = pcall(hs.json.decode, output)
  if not ok then
    hs.alert.show("Failed to parse wt-git.sh output")
    return nil
  end
  if type(result) == "table" and result.error then
    hs.alert.show("Error: " .. result.error)
    return nil
  end
  return result
end

local function timeAgo(isoTimestamp)
  if not isoTimestamp or isoTimestamp == "" then return "" end
  local y, mo, d, h, mi, s = isoTimestamp:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
  if not y then return "" end
  local t = os.time({year=tonumber(y), month=tonumber(mo), day=tonumber(d),
                      hour=tonumber(h), min=tonumber(mi), sec=tonumber(s)})
  local diff = os.time() - t
  if diff < 60 then return "just now"
  elseif diff < 3600 then return math.floor(diff/60) .. "m ago"
  elseif diff < 86400 then return math.floor(diff/3600) .. "h ago"
  elseif diff < 604800 then return math.floor(diff/86400) .. "d ago"
  else return math.floor(diff/604800) .. "w ago" end
end

local function repoColor(repoName)
  for _, entry in ipairs(layouts.repoColors) do
    if entry.repo == repoName then
      local c = layouts.colorPalette[entry.color]
      if c then return c end
    end
  end
  return layouts.colorPalette.gray
end

-- Filled circle (existing repos/worktrees)
local dotCache = {}
local function colorDot(rgb, alpha)
  alpha = alpha or 1.0
  local key = string.format("fill:%.2f,%.2f,%.2f,%.2f", rgb[1], rgb[2], rgb[3], alpha)
  if dotCache[key] then return dotCache[key] end
  local size = 24
  local canvas = hs.canvas.new({x=0, y=0, w=size, h=size})
  canvas[1] = {
    type = "circle",
    center = {x = size/2, y = size/2},
    radius = size/2 - 2,
    fillColor = {red=rgb[1], green=rgb[2], blue=rgb[3], alpha=alpha},
    action = "fill",
  }
  local img = canvas:imageFromCanvas()
  canvas:delete()
  dotCache[key] = img
  return img
end

-- Indented filled circle (worktree sub-entries)
local function colorDotIndented(rgb, alpha)
  alpha = alpha or 1.0
  local key = string.format("ifill:%.2f,%.2f,%.2f,%.2f", rgb[1], rgb[2], rgb[3], alpha)
  if dotCache[key] then return dotCache[key] end
  local size = 24
  local indent = 8
  local dotSize = 14
  local canvas = hs.canvas.new({x=0, y=0, w=size, h=size})
  canvas[1] = {
    type = "circle",
    center = {x = indent + dotSize/2, y = size/2},
    radius = dotSize/2 - 1,
    fillColor = {red=rgb[1], green=rgb[2], blue=rgb[3], alpha=alpha},
    action = "fill",
  }
  local img = canvas:imageFromCanvas()
  canvas:delete()
  dotCache[key] = img
  return img
end

-- Ring/hollow circle (create/new actions)
local function colorRing(rgb, alpha)
  alpha = alpha or 1.0
  local key = string.format("ring:%.2f,%.2f,%.2f,%.2f", rgb[1], rgb[2], rgb[3], alpha)
  if dotCache[key] then return dotCache[key] end
  local size = 24
  local canvas = hs.canvas.new({x=0, y=0, w=size, h=size})
  canvas[1] = {
    type = "circle",
    center = {x = size/2, y = size/2},
    radius = size/2 - 2,
    strokeColor = {red=rgb[1], green=rgb[2], blue=rgb[3], alpha=alpha},
    strokeWidth = 2.5,
    action = "stroke",
  }
  local img = canvas:imageFromCanvas()
  canvas:delete()
  dotCache[key] = img
  return img
end

-- Main entry point: flat repo list
-- Enter = open main, worktree sub-entries for repos that have them
function M.show()
  local repos = runGit("list-repos")
  if not repos then return end

  -- Priority repos in config order, then non-priority by most recent commit
  table.sort(repos, function(a, b)
    local pa = repoPriority[a.name]
    local pb = repoPriority[b.name]
    if pa and pb then return pa < pb end  -- both priority: config order
    if pa and not pb then return true end  -- priority before non-priority
    if not pa and pb then return false end
    return (a.lastCommit or "") > (b.lastCommit or "")  -- both non-priority: recency
  end)

  -- Gather worktrees for all repos that have them
  local repoWorktrees = {}
  for _, repo in ipairs(repos) do
    if repo.worktreeCount > 0 then
      repoWorktrees[repo.name] = runGit("list-worktrees", repo.name) or {}
    end
  end

  local choices = {}
  for _, repo in ipairs(repos) do
    local age = timeAgo(repo.lastCommit)
    local rgb = repoColor(repo.name)

    -- Main entry: selecting opens main directly
    table.insert(choices, {
      text = hs.styledtext.new(repo.name, {color = {red=rgb[1], green=rgb[2], blue=rgb[3], alpha = repoPriority[repo.name] and 1.0 or 0.3}}),
      subText = (repo.lastCommitMessage or "") .. "  ·  " .. age,
      image = colorDot(rgb),
      _action = "open-main",
      _repo = repo.name,
    })

    -- Inline worktrees directly below their repo
    local wts = repoWorktrees[repo.name]
    if wts then
      table.sort(wts, function(a, b)
        return (a.lastCommit or "") > (b.lastCommit or "")
      end)
      for _, wt in ipairs(wts) do
        local wtAge = timeAgo(wt.lastCommit)
        local mergedTag = wt.merged and " merged" or ""
        table.insert(choices, {
          text = hs.styledtext.new("   " .. wt.name, {color = {red=rgb[1], green=rgb[2], blue=rgb[3], alpha = wt.merged and 0.5 or 1.0}}),
          subText = "   " .. repo.name .. "  ·  " .. (wt.lastCommitMessage or "") .. "  ·  " .. wtAge .. mergedTag,
          image = colorDotIndented(rgb, wt.merged and 0.4 or 0.75),
          _action = "open-worktree",
          _repo = repo.name,
          _name = wt.name,
          _path = wt.path,
          _merged = wt.merged,
        })
      end
    end
  end

  -- "New worktree..." at the bottom (always)
  table.insert(choices, {
    text = "New worktree...",
    subText = "Create a new worktree for any repo",
    image = colorRing(layouts.colorPalette.gray),
    _action = "new-worktree",
  })

  local chooser = hs.chooser.new(function(choice)
    if not choice then return end
    if choice._action == "open-main" then
      M._openWorktree(choice._repo, "main", false)
    elseif choice._action == "open-worktree" then
      M._openWorktree(choice._repo, choice._name, false)
    elseif choice._action == "new-worktree" then
      hs.timer.doAfter(0.05, function()
        M._showNewWorktreeRepos(repos)
      end)
    end
  end)

  chooser:placeholderText("Open repository or manage worktrees...")
  chooser:choices(choices)
  chooser:show()
end

-- Repo picker for "New worktree..." → then step 2
function M._showNewWorktreeRepos(repos)
  local choices = {}
  for _, repo in ipairs(repos) do
    table.insert(choices, {
      text = repo.name,
      subText = "Create worktree in " .. repo.name,
      image = colorRing(repoColor(repo.name)),
      _repo = repo.name,
    })
  end

  local chooser = hs.chooser.new(function(choice)
    if not choice then return end
    hs.timer.doAfter(0.05, function()
      M._showWorktrees(choice._repo)
    end)
  end)

  chooser:placeholderText("Create worktree in which repo?")
  chooser:choices(choices)
  chooser:show()
end

-- Step 2: Worktree chooser (for drill-in and new worktree)
function M._showWorktrees(repo)
  local worktrees = runGit("list-worktrees", repo) or {}

  table.sort(worktrees, function(a, b)
    return (a.lastCommit or "") > (b.lastCommit or "")
  end)

  local rgb = repoColor(repo)

  local function buildChoices(query)
    local choices = {}

    -- Dynamic "Create:" entry when typing a new name
    if query and query ~= "" then
      local matches = false
      if query == "main" then matches = true end
      for _, wt in ipairs(worktrees) do
        if wt.name == query then matches = true; break end
      end
      if not matches then
        table.insert(choices, {
          text = "Create: " .. query,
          subText = "New worktree on branch claude/" .. query,
          image = colorRing(rgb),
          _repo = repo,
          _name = query,
          _action = "create",
        })
      end
    end

    -- "main" entry
    table.insert(choices, {
      text = "main",
      subText = "Open main repository",
      image = colorDot(rgb),
      _repo = repo,
      _name = "main",
      _action = "open",
    })

    -- Existing worktrees
    for _, wt in ipairs(worktrees) do
      local age = timeAgo(wt.lastCommit)
      local mergedTag = wt.merged and " merged" or ""
      local sub = (wt.lastCommitMessage or "") .. "  ·  " .. age .. mergedTag

      table.insert(choices, {
        text = wt.name,
        subText = sub,
        image = colorDot(rgb, wt.merged and 0.4 or 0.75),
        _repo = repo,
        _name = wt.name,
        _action = "open",
        _merged = wt.merged,
        _path = wt.path,
      })

      if wt.merged then
        table.insert(choices, {
          text = "   Delete: " .. wt.name,
          subText = "   Merged -- safe to remove",
          image = colorDot({0.96, 0.26, 0.21}, 0.6),
          _repo = repo,
          _name = wt.name,
          _action = "delete",
        })
      end
    end

    return choices
  end

  local chooser = hs.chooser.new(function(choice)
    if not choice then return end
    if choice._action == "delete" then
      M.cleanup(choice._repo, choice._name)
    elseif choice._action == "create" then
      M._openWorktree(choice._repo, choice._name, true)
    else
      M._openWorktree(choice._repo, choice._name, false)
    end
  end)

  chooser:queryChangedCallback(function(query)
    chooser:choices(buildChoices(query))
  end)

  chooser:placeholderText("Select or type new worktree name for " .. repo .. "...")
  chooser:choices(buildChoices(""))
  chooser:show()
end

-- Open/create worktree and launch Ghostty
function M._openWorktree(repo, name, needsCreate)
  local worktreeDir

  if name == "main" then
    worktreeDir = WORKSPACE .. "/" .. repo
  elseif not needsCreate then
    local worktrees = runGit("list-worktrees", repo) or {}
    for _, wt in ipairs(worktrees) do
      if wt.name == name then
        worktreeDir = wt.path
        break
      end
    end
    if not worktreeDir then
      hs.alert.show("Worktree not found: " .. name)
      return
    end
  end

  if needsCreate then
    hs.alert.show("Creating worktree " .. repo .. "/" .. name .. "...")
    local task = hs.task.new(SCRIPT, function(exitCode, stdout, stderr)
      if exitCode ~= 0 then
        hs.alert.show("Failed to create worktree")
        print("wt-git.sh create error: " .. (stderr or ""))
        return
      end
      local ok, result = pcall(hs.json.decode, stdout)
      if not ok or not result or result.error then
        hs.alert.show("Error: " .. (result and result.error or "parse error"))
        return
      end
      worktreeDir = result.path
      M._launchGhostty(worktreeDir, repo, name)
    end, {"create", repo, name})
    task:start()
  else
    M._launchGhostty(worktreeDir, repo, name)
  end
end

function M._launchGhostty(dir, repo, name)
  local script = string.format([[
    tell application "Ghostty"
      activate
      set cfg to new surface configuration
      set initial working directory of cfg to "%s"
      set command of cfg to "/bin/zsh -lc 'source $HOME/.claude/profile && exec zsh -l'"
      set win to new window with configuration cfg
    end tell
  ]], dir)

  local ok, result, descriptor = hs.osascript.applescript(script)
  if not ok then
    hs.alert.show("Failed to launch Ghostty")
    print("AppleScript error: " .. tostring(descriptor))
    return
  end

  hs.alert.show(repo .. "/" .. name .. " ready")
end

-- Cleanup worktree
function M.cleanup(repo, name)
  if name == "main" then
    hs.alert.show("Cannot delete main")
    return
  end

  local ok, result = hs.osascript.applescript(string.format([[
    display dialog "Remove %s/%s and delete branch claude/%s?" buttons {"Cancel", "Delete"} default button "Cancel" with icon caution with title "Delete worktree?"
  ]], repo, name, name))
  if not ok or not result or not tostring(result):find("Delete") then return end

  M._closeGhosttyByCwd(repo, name)

  hs.alert.show("Removing " .. repo .. "/" .. name .. "...")
  local task = hs.task.new(SCRIPT, function(exitCode, stdout, stderr)
    if exitCode ~= 0 then
      hs.alert.show("Failed to remove worktree")
      print("wt-git.sh remove error: " .. (stderr or ""))
      return
    end
    hs.alert.show(repo .. "/" .. name .. " removed")
  end, {"remove", repo, name})
  task:start()
end

function M._closeGhosttyByCwd(repo, name)
  local worktreeDir = WORKSPACE .. "/worktrees/" .. repo .. "/" .. name
  local shellPids = {}

  local psOutput = hs.execute(
    "for pid in $(pgrep -x ghostty 2>/dev/null); do "
    .. "for login in $(pgrep -P $pid 2>/dev/null); do "
    .. "for shell in $(pgrep -P $login 2>/dev/null); do "
    .. "cwd=$(lsof -a -d cwd -Fn -p $shell 2>/dev/null | grep ^n | head -1 | cut -c2-); "
    .. "echo \"$shell|$cwd\"; "
    .. "done; done; done"
  )

  if not psOutput then return end

  for line in psOutput:gmatch("[^\n]+") do
    local shellPid, cwd = line:match("^(%d+)|(.*)")
    if cwd and (cwd == worktreeDir or cwd:sub(1, #worktreeDir + 1) == worktreeDir .. "/") then
      table.insert(shellPids, shellPid)
    end
  end

  for _, pid in ipairs(shellPids) do
    hs.execute("kill " .. pid .. " 2>/dev/null")
  end
end

return M
