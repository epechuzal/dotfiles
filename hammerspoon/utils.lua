local M = {}

function M.findScreen(hint)
  if hint == nil or hint == "main" then
    return hs.screen.mainScreen()
  end

  if hint == "iPad" then
    for _, s in ipairs(hs.screen.allScreens()) do
      local name = s:name()
      if name == nil or name == "" or name == "(un-named screen)" then
        return s
      end
    end
    return nil
  end

  if type(hint) == "number" then
    local screens = hs.screen.allScreens()
    return screens[hint]
  end

  return hs.screen.find(hint)
end

function M.positionWindow(win, position, screen)
  if not win then return false end

  screen = screen or win:screen() or hs.screen.mainScreen()
  local frame = screen:frame()

  local newFrame = {
    x = frame.x + (frame.w * position[1]),
    y = frame.y + (frame.h * position[2]),
    w = frame.w * position[3],
    h = frame.h * position[4],
  }

  win:setFrame(newFrame)
  return true
end

function M.findWindows(appName, titlePattern)
  local results = {}

  -- Scan all running instances of the app (some apps like Ghostty
  -- run a separate process per window)
  for _, app in ipairs(hs.application.runningApplications()) do
    if app:name() == appName then
      for _, win in ipairs(app:allWindows()) do
        local title = win:title() or ""
        if title ~= "" then
          if titlePattern == nil or string.find(title, titlePattern) then
            table.insert(results, win)
          end
        end
      end
    end
  end

  return results
end

function M.windowToChoice(win)
  local app = win:application()
  return {
    text = (app and app:name() or "Unknown") .. " — " .. (win:title() or "untitled"),
    subText = "Screen: " .. (win:screen():name() or "unknown"),
    windowId = win:id(),
    image = app and hs.image.imageFromAppBundle(app:bundleID()) or nil,
  }
end

function M.allWindowChoices(filterApp)
  local choices = {}
  local windows = hs.window.allWindows()

  for _, win in ipairs(windows) do
    local title = win:title() or ""
    if title ~= "" then
      local app = win:application()
      local appName = app and app:name() or ""
      if filterApp == nil or appName == filterApp then
        table.insert(choices, M.windowToChoice(win))
      end
    end
  end

  return choices
end

function M.windowById(id)
  return hs.window.get(id)
end

return M
