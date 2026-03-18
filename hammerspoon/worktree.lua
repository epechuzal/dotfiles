local layouts = require("layouts")

local M = {}

local SCRIPT = os.getenv("HOME") .. "/Workspace/dotfiles/hammerspoon/scripts/wt-git.sh"
local WORKSPACE = os.getenv("HOME") .. "/Workspace"

local repoPriority = {}
for i, entry in ipairs(layouts.repoColors) do
  repoPriority[entry.repo] = i
end
local defaultPriority = #layouts.repoColors + 1

local REMOTE_SCRIPT = "~/Workspace/dotfiles/hammerspoon/scripts/wt-git.sh"
local TAILSCALE = "/usr/local/bin/tailscale"

local function isHostReachable(host)
  if not host.tailscaleIP then return true end
  local _, status = hs.execute(TAILSCALE .. " status 2>/dev/null | grep " .. host.tailscaleIP .. " | grep -qv offline")
  return status == true
end

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

local function runGitRemote(host, ...)
  local args = table.concat({...}, " ")
  local cmd = string.format("ssh -o ConnectTimeout=3 %s '%s %s'", host.ssh, REMOTE_SCRIPT, args)
  local output, status = hs.execute(cmd)
  if not status then return nil end
  local ok, result = pcall(hs.json.decode, output)
  if not ok then return nil end
  if type(result) == "table" and result.error then return nil end
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

-- SF Symbol icon generation
local SCRIPTS_DIR = os.getenv("HOME") .. "/Workspace/dotfiles/hammerspoon/scripts"
local SF_ICON_BIN = SCRIPTS_DIR .. "/sf-icon"
local SF_ICON_SRC = SCRIPTS_DIR .. "/sf-icon.swift"
local ICON_CACHE_DIR = os.getenv("HOME") .. "/.hammerspoon/icon-cache"

-- Compile sf-icon binary if needed
local function ensureSfIconBin()
  local f = io.open(SF_ICON_BIN, "r")
  if f then f:close(); return true end
  local _, ok = hs.execute("swiftc " .. SF_ICON_SRC .. " -framework AppKit -o " .. SF_ICON_BIN .. " 2>&1")
  if not ok then
    print("[worktree] Failed to compile sf-icon")
    return false
  end
  return true
end

hs.execute("mkdir -p " .. ICON_CACHE_DIR)
local sfIconReady = ensureSfIconBin()

local iconCache = {}
local function sfIcon(symbol, rgb, alpha)
  alpha = alpha or 1.0
  local key = string.format("%s:%.2f,%.2f,%.2f,%.2f", symbol, rgb[1], rgb[2], rgb[3], alpha)
  if iconCache[key] then return iconCache[key] end

  if not sfIconReady then return nil end

  local path = string.format("%s/%s_%.0f_%.0f_%.0f_%.0f.png",
    ICON_CACHE_DIR, symbol:gsub("%.", "_"), rgb[1]*255, rgb[2]*255, rgb[3]*255, alpha*100)

  -- Generate if not on disk
  local f = io.open(path, "r")
  if f then
    f:close()
  else
    local cmd = string.format("%s %s %.3f %.3f %.3f %.3f %s 48",
      SF_ICON_BIN, symbol, rgb[1], rgb[2], rgb[3], alpha, path)
    hs.execute(cmd)
  end

  local img = hs.image.imageFromPath(path)
  if img then
    img = img:setSize({w=24, h=24})
    iconCache[key] = img
  end
  return img
end

-- Icon helpers: local repos = laptop, remote repos = cloud, actions = plus.circle
local function localIcon(rgb, alpha)
  return sfIcon("laptopcomputer", rgb, alpha)
end

local function localIconSub(rgb, alpha)
  return sfIcon("arrow.turn.down.right", rgb, alpha or 0.75)
end

local function remoteIcon(rgb, alpha)
  return sfIcon("cloud.fill", rgb, alpha)
end

local function remoteIconSub(rgb, alpha)
  return sfIcon("cloud", rgb, alpha or 0.75)
end

local function actionIcon(rgb, alpha)
  return sfIcon("plus.circle", rgb, alpha)
end

-- Wire up fn+delete (forward delete) on a chooser to trigger worktree deletion
local function attachDeleteKey(chooser)
  local tap
  tap = hs.eventtap.new({hs.eventtap.event.types.keyDown}, function(event)
    local keyCode = event:getKeyCode()
    -- 51 = backspace, 117 = forward delete
    if keyCode ~= 51 and keyCode ~= 117 then return false end
    -- Only intercept when query is empty (otherwise user is editing search text)
    if keyCode == 51 and (chooser:query() or "") ~= "" then return false end

    local row = chooser:selectedRowContents()
    print("[worktree-delete] key=" .. keyCode .. " row=" .. hs.inspect(row))
    if not row or not row._name or row._name == "main" then return false end
    if row._action ~= "open-worktree" and row._action ~= "open" then return false end

    local repo = row._repo
    local name = row._name
    local remote = row._remote
    print("[worktree-delete] deleting " .. repo .. "/" .. name .. (remote and " (remote:" .. remote.name .. ")" or ""))
    chooser:cancel()
    hs.timer.doAfter(0.1, function()
      print("[worktree-delete] timer fired, calling cleanup")
      M.cleanup(repo, name, remote)
    end)
    return true
  end)

  chooser:showCallback(function() tap:start() end)
  chooser:hideCallback(function() tap:stop() end)
  return chooser
end

local function sortRepos(repos)
  table.sort(repos, function(a, b)
    local pa = repoPriority[a.name]
    local pb = repoPriority[b.name]
    if pa and pb then
      if pa ~= pb then return pa < pb end
      if a._remote ~= b._remote then return not a._remote end
    end
    if pa and not pb then return true end
    if not pa and pb then return false end
    if (not a._remote) ~= (not b._remote) then return not a._remote end
    return (a.lastCommit or "") > (b.lastCommit or "")
  end)
end

local function buildChoicesFromRepos(repos, repoWorktrees)
  local choices = {}
  for _, repo in ipairs(repos) do
    local age = timeAgo(repo.lastCommit)
    local rgb = repoColor(repo.name)
    local isRemote = repo._remote ~= nil
    local hostLabel = isRemote and repo._remote.name or nil
    local wtKey = (isRemote and repo._remote.name .. ":" or "") .. repo.name

    local nameDisplay = isRemote and (repo.name .. "  " .. hostLabel) or repo.name
    table.insert(choices, {
      text = hs.styledtext.new(nameDisplay, {color = {red=rgb[1], green=rgb[2], blue=rgb[3], alpha = repoPriority[repo.name] and 1.0 or 0.3}}),
      subText = (repo.lastCommitMessage or "") .. "  ·  " .. age,
      image = isRemote and remoteIcon(rgb) or localIcon(rgb),
      _action = "open-main",
      _repo = repo.name,
      _remote = repo._remote,
    })

    local wts = repoWorktrees[wtKey]
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
          image = isRemote and remoteIconSub(rgb, wt.merged and 0.4 or 0.75) or localIconSub(rgb, wt.merged and 0.4 or 0.75),
          _action = "open-worktree",
          _repo = repo.name,
          _name = wt.name,
          _path = wt.path,
          _merged = wt.merged,
          _remote = repo._remote,
        })
      end
    end
  end

  table.insert(choices, {
    text = "New worktree...",
    subText = "Create a new worktree for any repo",
    image = actionIcon(layouts.colorPalette.gray),
    _action = "new-worktree",
  })

  return choices
end

local function choiceMatchesQuery(choice, query)
  if not query or query == "" then return true end
  query = query:lower()
  local text = choice._repo or ""
  local name = choice._name or ""
  local action = choice._action or ""
  if action == "new-worktree" then return true end
  return text:lower():find(query, 1, true) or name:lower():find(query, 1, true)
end

-- Main entry point: flat repo list
-- Enter = open main, worktree sub-entries for repos that have them
function M.show()
  local repos = runGit("list-repos")
  if not repos then repos = {} end
  for _, repo in ipairs(repos) do repo._remote = nil end

  -- Gather local worktrees
  local repoWorktrees = {}
  for _, repo in ipairs(repos) do
    if repo.worktreeCount > 0 then
      repoWorktrees[repo.name] = runGit("list-worktrees", repo.name) or {}
    end
  end

  sortRepos(repos)
  local allRepos = {}
  for _, r in ipairs(repos) do table.insert(allRepos, r) end

  local chooser
  local remoteLoading = false

  local dismissed = false

  local function refreshChoices()
    if dismissed then return end
    local query = chooser and chooser:query() or ""
    local choices = buildChoicesFromRepos(allRepos, repoWorktrees)
    if query ~= "" then
      local filtered = {}
      for _, c in ipairs(choices) do
        if choiceMatchesQuery(c, query) then table.insert(filtered, c) end
      end
      choices = filtered
    end
    if remoteLoading then
      table.insert(choices, 1, {
        text = hs.styledtext.new("Loading remote worktrees...", {color = {red=0.5, green=0.5, blue=0.5, alpha=0.6}}),
        subText = "",
        image = sfIcon("arrow.triangle.2.circlepath", {0.5, 0.5, 0.5}, 0.5),
        _action = "noop",
      })
    end
    chooser:choices(choices)
  end

  chooser = hs.chooser.new(function(choice)
    dismissed = true
    if not choice or choice._action == "noop" then return end
    if choice._action == "open-main" then
      if choice._remote then
        M._openRemote(choice._remote, choice._repo, "main")
      else
        M._openWorktree(choice._repo, "main", false)
      end
    elseif choice._action == "open-worktree" then
      if choice._remote then
        M._openRemote(choice._remote, choice._repo, choice._name)
      else
        M._openWorktree(choice._repo, choice._name, false)
      end
    elseif choice._action == "new-worktree" then
      hs.timer.doAfter(0.05, function()
        M._showNewWorktreeRepos(allRepos)
      end)
    end
  end)

  attachDeleteKey(chooser)
  chooser:placeholderText("Open repository or manage worktrees...")
  refreshChoices()
  chooser:show()

  -- Async fetch remote repos
  local remoteHosts = {}
  for _, host in ipairs(layouts.remoteHosts or {}) do
    if isHostReachable(host) then table.insert(remoteHosts, host) end
  end

  if #remoteHosts == 0 then return end

  remoteLoading = true
  refreshChoices()
  local pendingTasks = 0
  local function taskDone()
    pendingTasks = pendingTasks - 1
    if pendingTasks == 0 then remoteLoading = false end
    refreshChoices()
  end

  local function fetchWorktreesAsync(host, reposWithWt)
    for _, repo in ipairs(reposWithWt) do
      pendingTasks = pendingTasks + 1
      local wtCmd = string.format("ssh -o ConnectTimeout=3 %s '%s list-worktrees %s'", host.ssh, REMOTE_SCRIPT, repo.name)
      hs.task.new("/bin/bash", function(wtExit, wtOut, _)
        if wtExit == 0 then
          local ok, wts = pcall(hs.json.decode, wtOut)
          if ok and wts and type(wts) == "table" and not wts.error then
            repoWorktrees[host.name .. ":" .. repo.name] = wts
          end
        end
        taskDone()
      end, {"-c", wtCmd}):start()
    end
  end

  for _, host in ipairs(remoteHosts) do
    pendingTasks = pendingTasks + 1
    local cmd = string.format("ssh -o ConnectTimeout=3 %s '%s list-repos'", host.ssh, REMOTE_SCRIPT)
    hs.task.new("/bin/bash", function(exitCode, stdout, _stderr)
      if exitCode ~= 0 then
        taskDone()
        return
      end

      local ok, remoteRepos = pcall(hs.json.decode, stdout)
      if not ok or not remoteRepos or remoteRepos.error then
        taskDone()
        return
      end

      -- Add repos to list and refresh immediately (shows repos before worktrees load)
      local reposWithWt = {}
      for _, repo in ipairs(remoteRepos) do
        repo._remote = host
        table.insert(allRepos, repo)
        if repo.worktreeCount > 0 then table.insert(reposWithWt, repo) end
      end
      sortRepos(allRepos)

      -- Fire off async worktree fetches
      if #reposWithWt > 0 then
        fetchWorktreesAsync(host, reposWithWt)
      end

      taskDone()
    end, {"-c", cmd}):start()
  end
end

-- Repo picker for "New worktree..." → then step 2
function M._showNewWorktreeRepos(repos)
  local choices = {}
  for _, repo in ipairs(repos) do
    table.insert(choices, {
      text = repo.name,
      subText = "Create worktree in " .. repo.name,
      image = actionIcon(repoColor(repo.name)),
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
          image = actionIcon(rgb),
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
      image = localIcon(rgb),
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
        image = localIconSub(rgb, wt.merged and 0.4 or 0.75),
        _repo = repo,
        _name = wt.name,
        _action = "open",
        _merged = wt.merged,
        _path = wt.path,
      })
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

  attachDeleteKey(chooser)
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
function M.cleanup(repo, name, remote)
  if name == "main" then
    hs.alert.show("Cannot delete main")
    return
  end

  -- Gather rich info before confirming
  local label = (remote and remote.name .. ":" or "") .. repo .. "/" .. name
  print("[worktree-cleanup] getting info for " .. label)
  local info
  if remote then
    info = runGitRemote(remote, "info", repo, name)
  else
    info = runGit("info", repo, name)
  end
  print("[worktree-cleanup] info result: " .. hs.inspect(info))
  if not info then
    hs.alert.show("Could not get worktree info")
    return
  end

  -- Build summary lines
  local lines = {}
  table.insert(lines, label)
  table.insert(lines, "Branch: " .. (info.branch or "unknown"))
  table.insert(lines, "")

  -- Status
  if info.merged then
    table.insert(lines, "✓ Merged into main")
  elseif info.diffFiles == 0 then
    table.insert(lines, "✓ No diff against main (likely squash-merged)")
  else
    table.insert(lines, "✗ NOT merged — " .. info.diffFiles .. " files differ from main")
    table.insert(lines, "  " .. info.ahead .. " commits ahead, " .. info.behind .. " behind")
  end

  if info.dirty then
    table.insert(lines, "⚠ Has uncommitted changes")
  end

  table.insert(lines, "")
  table.insert(lines, "Last commit: " .. timeAgo(info.lastCommit))
  table.insert(lines, info.lastCommitMessage or "")

  local message = table.concat(lines, "\n")

  local button = hs.dialog.blockAlert("Delete worktree?", message, "Delete", "Cancel")
  if button ~= "Delete" then return end

  if remote then
    hs.alert.show("Removing " .. label .. "...")
    local cmd = string.format("ssh -o ConnectTimeout=3 %s '%s remove %s %s'", remote.ssh, REMOTE_SCRIPT, repo, name)
    local _, ok = hs.execute(cmd)
    if ok then
      hs.alert.show(label .. " removed")
    else
      hs.alert.show("Failed to remove remote worktree")
    end
  else
    M._closeGhosttyByCwd(repo, name)

    hs.alert.show("Removing " .. label .. "...")
    local task = hs.task.new(SCRIPT, function(exitCode, stdout, stderr)
      if exitCode ~= 0 then
        hs.alert.show("Failed to remove worktree")
        print("wt-git.sh remove error: " .. (stderr or ""))
        return
      end
      hs.alert.show(label .. " removed")
    end, {"remove", repo, name})
    task:start()
  end
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

-- Open a remote repo/worktree via SSH in Ghostty
function M._openRemote(host, repo, name)
  local remoteDir
  if name == "main" then
    remoteDir = "~/Workspace/" .. repo
  else
    local worktrees = runGitRemote(host, "list-worktrees", repo) or {}
    for _, wt in ipairs(worktrees) do
      if wt.name == name then
        remoteDir = wt.path
        break
      end
    end
    if not remoteDir then
      hs.alert.show("Remote worktree not found: " .. name)
      return
    end
  end

  local sshCmd = string.format("ssh -t %s 'cd %s && exec zsh -l'", host.ssh, remoteDir)
  local script = string.format([[
    tell application "Ghostty"
      activate
      set cfg to new surface configuration
      set command of cfg to "%s"
      set win to new window with configuration cfg
    end tell
  ]], sshCmd)

  local ok, result, descriptor = hs.osascript.applescript(script)
  if not ok then
    hs.alert.show("Failed to launch Ghostty")
    print("AppleScript error: " .. tostring(descriptor))
    return
  end

  hs.alert.show(host.name .. ":" .. repo .. "/" .. name .. " ready")
end

return M
