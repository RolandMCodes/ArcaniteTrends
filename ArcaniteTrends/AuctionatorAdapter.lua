local _, A = ...
local Core = A.Core
local Adapter = {}
A.Adapter = Adapter

local CALLER = "ArcaniteTrends"
local DEBOUNCE = 0.35
local RETRY = 0.5
local TIMEOUT = 30
local scheduled, deadline, registered, onChange
local sessionDay

local function now()
  return time()
end

function Adapter.Today()
  local epoch = Auctionator and Auctionator.Constants and Auctionator.Constants.SCAN_DAY_0
  if type(epoch) ~= "number" then epoch = time({year = 2020, month = 1, day = 1, hour = 0}) end
  return math.floor((now() - epoch) / 86400)
end

local function activeMarket()
  -- Follow the same realm/faction identity as Auctionator's Classic database.
  if type(GetRealmName) ~= "function" or type(UnitFactionGroup) ~= "function" then return nil end
  local realm, faction = GetRealmName(), UnitFactionGroup("player")
  if not realm or not faction then return nil end
  return realm .. " " .. faction
end

local function setState(state, message)
  A.runtime = {state = state, message = message}
  if onChange then onChange() end
end

local function compatible()
  if type(Auctionator) ~= "table" or type(Auctionator.Database) ~= "table" then
    return nil, "Waiting for Auctionator to initialize its price history.", "waiting"
  end
  local database = Auctionator.Database
  local api = Auctionator.API and Auctionator.API.v1
  if type(database.GetPriceHistory) ~= "function" or type(api) ~= "table"
    or type(api.GetAuctionPriceByItemID) ~= "function" or type(api.RegisterForDBUpdate) ~= "function" then
    return nil, "Auctionator's history interface changed. Saved charts are still available.", "error"
  end
  if type(database.db) == "table" and database.db.version ~= nil and database.db.version ~= 2 then
    return nil, "Auctionator's database version is unsupported. Saved charts are still available.", "error"
  end
  return database, api
end

local function processing(database)
  local ticker = database.ticker
  if ticker == nil then return false end
  local tickerType = type(ticker)
  if (tickerType ~= "table" and tickerType ~= "userdata") or type(ticker.IsCancelled) ~= "function" then
    return nil, "Auctionator's processing interface changed. Saved charts are still available."
  end
  local ok, cancelled = pcall(ticker.IsCancelled, ticker)
  if not ok or type(cancelled) ~= "boolean" then
    return nil, "Unable to determine whether Auctionator finished processing."
  end
  return not cancelled
end

function Adapter.DecodeHistory(itemId, history)
  if type(history) ~= "table" or #history > 100000 then return nil, "Invalid Auctionator history." end
  local rows = {}
  local count = 0
  for key, entry in pairs(history) do
    count = count + 1
    if count > 100000 or type(key) ~= "number" or key < 1 or key > #history or key ~= math.floor(key)
      or type(entry) ~= "table" then
      return nil, "Auctionator's history interface changed."
    end
    local day = (type(entry.rawDay) == "string" or type(entry.rawDay) == "number") and tonumber(entry.rawDay)
    local row, err = Core.ValidateRow({itemId = itemId, day = day,
      low = entry.minSeen, high = entry.maxSeen, maxAvailable = entry.available})
    if not row then
      -- Empty price observations contain no usable history, but are not zeroes.
      if err ~= "Empty observation." then return nil, err end
    else
      rows[#rows + 1] = row
    end
  end
  return rows
end

function Adapter.Capture(db)
  if activeMarket() ~= Core.MARKET then
    return nil, "Collection paused on this character. Showing saved Mankrik Alliance history.", "paused"
  end
  local database, api, state = compatible()
  if not database then return nil, api, state end
  local busy, err = processing(database)
  if busy == nil then return nil, err, "error" end
  if busy then return nil, "Waiting for Auctionator to finish processing this scan.", "waiting" end
  local pendingRows, pendingLatest = {}, {}
  for _, item in ipairs(Core.ITEMS) do
    local ok, history = pcall(database.GetPriceHistory, database, tostring(item.itemId))
    if not ok then return nil, "Unable to read Auctionator's price history. Saved charts are still available.", "error" end
    local rows, decodeError = Adapter.DecodeHistory(item.itemId, history)
    if not rows then return nil, decodeError, "error" end
    local latestDay
    for _, row in ipairs(rows) do
      if row.day > Adapter.Today() then return nil, "Auctionator returned a future observation day.", "error" end
      pendingRows[#pendingRows + 1] = row
      if (row.low or row.high) and (not latestDay or row.day > latestDay) then latestDay = row.day end
    end
    local priceOK, price = pcall(api.GetAuctionPriceByItemID, CALLER, item.itemId)
    if not priceOK or (price ~= nil and price ~= 0 and not Core.IsPrice(price)) then
      return nil, "Auctionator returned an invalid last-seen price.", "error"
    end
    if latestDay and Core.IsPrice(price) then
      pendingLatest[#pendingLatest + 1] = {itemId = item.itemId, price = price, day = latestDay}
    end
  end
  -- Stage all three items before committing; one malformed item preserves the
  -- preceding complete companion state rather than causing a partial update.
  Core.MergeRows(db, pendingRows)
  for _, latest in ipairs(pendingLatest) do Core.MergeLatest(db, latest.itemId, latest.price, latest.day) end
  db.lastSyncedAt = now()
  if sessionDay and Adapter.Today() ~= sessionDay then
    return true, "Auctionator's recorded day may still be the prior day for this session. Use /reload to start its new day bucket.", "warning"
  end
  return true, "Auctionator history checked. Each item retains its own recorded observation day.", "ready"
end

local attempt
local function schedule(delay)
  if scheduled then return end
  scheduled = true
  C_Timer.After(delay, function()
    scheduled = false
    attempt()
  end)
end

attempt = function()
  if activeMarket() ~= Core.MARKET then
    deadline = nil
    setState("paused", "Collection paused on this character. Showing saved Mankrik Alliance history.")
    return
  end
  local database, api, state = compatible()
  if database and not registered then
    local ok = pcall(api.RegisterForDBUpdate, CALLER, function() Adapter.RequestRefresh("database-update") end)
    if not ok then
      deadline = nil
      setState("error", "Unable to subscribe to Auctionator updates. Saved charts are still available.")
      return
    end
    registered = true
  end
  local succeeded, message
  if database then
    succeeded, message, state = Adapter.Capture(A.db)
  else
    message = api
  end
  if not succeeded and state == "waiting" then
    if GetTime() >= deadline then
      deadline = nil
      setState("error", "Auctionator did not finish within 30 seconds. Saved charts are preserved; reopen this window or complete another scan to retry.")
      return
    end
    setState(state, message)
    schedule(RETRY)
    return
  end
  deadline = nil
  setState(state or "error", message or "Unable to refresh Auctionator history.")
end

function Adapter.RequestRefresh(reason)
  if not A.db then return end
  if not deadline then deadline = GetTime() + TIMEOUT end
  schedule(DEBOUNCE)
end

function Adapter.Start(callback)
  if onChange then return end
  onChange = callback or function() end
  sessionDay = Adapter.Today()
  Adapter.RequestRefresh("login")
end
