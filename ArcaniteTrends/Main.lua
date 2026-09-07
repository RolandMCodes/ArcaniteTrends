local addonName, A = ...
local frame = CreateFrame("Frame")
local loaded, started, persistenceError

local function updateUI()
  if A.UI and A.UI.Refresh then A.UI.Refresh() end
end

function A.RequestRefresh(reason)
  if persistenceError then
    A.runtime = {state = "error", message = persistenceError}
    updateUI()
    return
  end
  A.Adapter.RequestRefresh(reason)
end

local function start()
  if not loaded or started then return end
  started = true
  if not persistenceError then A.Adapter.Start(updateUI) end
end

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, event, name)
  if event == "ADDON_LOADED" and name == addonName and not loaded then
    loaded = true
    A.db, persistenceError = A.Core.InitDB(ArcaniteTrendsDB)
    if not A.db then
      A.db = A.Core.InitDB(nil)
      A.runtime = {state = "error", message = persistenceError}
    else
      ArcaniteTrendsDB = A.db
      local _, seedError = A.Core.MergeSeed(A.db, A.Seed)
      A.runtime = {state = seedError and "warning" or "waiting",
        message = seedError or "Waiting for Auctionator's saved history."}
    end
    A.UI.Initialize()
    updateUI()
    frame:UnregisterEvent("ADDON_LOADED")
    if type(IsLoggedIn) == "function" and IsLoggedIn() then start() end
  elseif event == "PLAYER_LOGIN" then
    start()
    frame:UnregisterEvent("PLAYER_LOGIN")
  end
end)
