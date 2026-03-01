local M = {}

M.apps = {
  "Spotify",
  "Docker Desktop",
  "iPhone Mirroring",
}

local watcher = nil

function M.start()
  watcher = hs.application.watcher.new(function(appName, eventType, app)
    if eventType == hs.application.watcher.deactivated then
      for _, name in ipairs(M.apps) do
        if appName == name and app then
          app:hide()
          return
        end
      end
    end
  end)
  watcher:start()
end

function M.stop()
  if watcher then
    watcher:stop()
    watcher = nil
  end
end

return M
