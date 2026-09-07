local _, A = ...

local Core = {}
A.Core = Core
Core.MARKET = "Mankrik Alliance"
Core.ITEMS = {
  {itemId = 12363, name = "Arcane Crystal", reference = "low"},
  {itemId = 12359, name = "Thorium Bar", reference = "low"},
  {itemId = 12360, name = "Arcanite Bar", reference = "high"},
}
local tracked = {[12363] = true, [12359] = true, [12360] = true}
local MAX_INTEGER = 9007199254740991

local function integer(value, minimum, maximum)
  return type(value) == "number" and value == value and value >= minimum
    and value <= maximum and value == math.floor(value)
end

function Core.IsDay(value)
  return integer(value, 0, 100000)
end

function Core.IsPrice(value)
  return integer(value, 1, MAX_INTEGER)
end

function Core.ValidateRow(row)
  if type(row) ~= "table" or not tracked[row.itemId] or not Core.IsDay(row.day) then
    return nil, "Invalid item or observation day."
  end
  local low, high = row.low, row.high
  if low == 0 then low = nil end
  if high == 0 then high = nil end
  if (low ~= nil and not Core.IsPrice(low)) or (high ~= nil and not Core.IsPrice(high)) then
    return nil, "Invalid copper price."
  end
  if low and high and low > high then return nil, "Daily low exceeds daily high." end
  local quantity = row.maxAvailable
  if quantity ~= nil and not integer(quantity, 0, MAX_INTEGER) then
    return nil, "Invalid observed availability."
  end
  if not low and not high and quantity == nil then return nil, "Empty observation." end
  return {itemId = row.itemId, day = row.day, low = low, high = high, maxAvailable = quantity}
end

local function market(db)
  return db.markets[Core.MARKET]
end

function Core.MergeRows(db, rows)
  local count = 0
  for _, candidate in ipairs(rows) do
    local row = Core.ValidateRow(candidate)
    if row then
      local days = market(db).daily[row.itemId]
      local old = days[row.day]
      local low = row.low
      local high = row.high
      local quantity = row.maxAvailable
      if old then
        if old.low then low = low and math.min(low, old.low) or old.low end
        if old.high then high = high and math.max(high, old.high) or old.high end
        if old.maxAvailable ~= nil then
          quantity = quantity ~= nil and math.max(quantity, old.maxAvailable) or old.maxAvailable
        end
      end
      if not old or low ~= old.low or high ~= old.high or quantity ~= old.maxAvailable then
        days[row.day] = {low = low, high = high, maxAvailable = quantity}
        count = count + 1
      end
    end
  end
  return count
end

function Core.MergeLatest(db, itemId, price, day)
  if not tracked[itemId] or not Core.IsPrice(price) or not Core.IsDay(day) then return false end
  local latest = market(db).latest
  local old = latest[itemId]
  if old and (old.day > day or (old.day == day and old.price == price)) then return false end
  latest[itemId] = {price = price, day = day}
  return true
end

function Core.InitDB(existing)
  if type(existing) == "table" and existing.schemaVersion ~= nil and existing.schemaVersion ~= 1 then
    return nil, "Saved history uses an unsupported version. It has been preserved."
  end
  local db = {schemaVersion = 1, markets = {}, ui = {}, seedImports = {}}
  db.markets[Core.MARKET] = {daily = {}, latest = {}}
  for _, item in ipairs(Core.ITEMS) do market(db).daily[item.itemId] = {} end
  if type(existing) ~= "table" then return db end
  if type(existing.ui) == "table" then db.ui = existing.ui end
  if integer(existing.lastSyncedAt, 0, MAX_INTEGER) then db.lastSyncedAt = existing.lastSyncedAt end
  if type(existing.seedImports) == "table" then
    for id, value in pairs(existing.seedImports) do
      if type(id) == "string" and #id <= 128 and value == true then db.seedImports[id] = true end
    end
  end
  local oldMarket = type(existing.markets) == "table" and existing.markets[Core.MARKET]
  if type(oldMarket) ~= "table" then return db end
  for _, item in ipairs(Core.ITEMS) do
    local id = item.itemId
    local oldDays = type(oldMarket.daily) == "table" and (oldMarket.daily[id] or oldMarket.daily[tostring(id)])
    if type(oldDays) == "table" then
      for day, entry in pairs(oldDays) do
        if type(entry) == "table" then
          Core.MergeRows(db, {{itemId = id, day = tonumber(day), low = entry.low,
            high = entry.high, maxAvailable = entry.maxAvailable}})
        end
      end
    end
    local latest = type(oldMarket.latest) == "table" and (oldMarket.latest[id] or oldMarket.latest[tostring(id)])
    if type(latest) == "table" then Core.MergeLatest(db, id, latest.price, latest.day) end
  end
  return db
end

function Core.MergeSeed(db, seed)
  if type(seed) ~= "table" or seed.version ~= 1 or seed.market ~= Core.MARKET
    or type(seed.id) ~= "string" or #seed.id > 128 or type(seed.rows) ~= "table" then
    return 0, "Unsupported seed history."
  end
  if db.seedImports[seed.id] then return 0 end
  if #seed.rows > 200000 then return 0, "Seed history is too large." end
  local rows = {}
  for _, entry in ipairs(seed.rows) do
    local row, err = Core.ValidateRow(entry)
    if not row then return 0, err end
    rows[#rows + 1] = row
  end
  local changed = Core.MergeRows(db, rows)
  db.seedImports[seed.id] = true
  return changed
end

-- Integer civil-date conversion keeps Auctionator raw days independent of DST.
local function civilDate(day)
  local z = day + 18262 + 719468
  local era = math.floor(z / 146097)
  local doe = z - era * 146097
  local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
  local year = yoe + era * 400
  local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
  local mp = math.floor((5 * doy + 2) / 153)
  local monthDay = doy - math.floor((153 * mp + 2) / 5) + 1
  local month = mp + (mp < 10 and 3 or -9)
  if month <= 2 then year = year + 1 end
  return year, month, monthDay
end

function Core.DateString(day)
  if not Core.IsDay(day) then return "Unknown date" end
  local year, month, monthDay = civilDate(day)
  return string.format("%04d-%02d-%02d", year, month, monthDay)
end

function Core.DayLabel(day)
  if not Core.IsDay(day) then return "?" end
  local _, month, monthDay = civilDate(day)
  return string.format("%d/%d", month, monthDay)
end

function Core.FormatCopper(value, signed)
  if type(value) ~= "number" or value ~= value or math.abs(value) > MAX_INTEGER then return "Unavailable" end
  local sign = value < 0 and "-" or (signed and value > 0 and "+" or "")
  value = math.abs(value)
  local whole = math.floor(value)
  value = whole + (value - whole >= 0.5 and 1 or 0)
  return string.format("%s%dg %ds %dc", sign, math.floor(value / 10000), math.floor(value / 100) % 100, value % 100)
end

function Core.Median(values)
  if #values == 0 then return nil end
  local sorted = {}
  for i, value in ipairs(values) do sorted[i] = value end
  table.sort(sorted)
  local n = #sorted
  if n % 2 == 1 then return sorted[(n + 1) / 2] end
  local a, b = sorted[n / 2], sorted[n / 2 + 1]
  return a + math.floor((b - a) / 2 + 0.5)
end

function Core.Net(price)
  -- Split whole hundreds to avoid intermediate multiplication losing integer
  -- precision for a large but otherwise valid copper value.
  return price - (math.floor(price / 100) * 5 + math.floor((price % 100) * 5 / 100))
end

function Core.BuildView(db, today)
  local stored = market(db)
  local startDay = today - 29
  local view = {today = today, startDay = startDay, charts = {}, lastSyncedAt = db.lastSyncedAt}
  for _, item in ipairs(Core.ITEMS) do
    local chart = {itemId = item.itemId, name = item.name, reference = item.reference,
      days = {}, coverage = 0, latest = stored.latest[item.itemId]}
    local history = stored.daily[item.itemId]
    for day = startDay, today do
      local row = history[day]
      local values = {}
      for windowDay = day - 6, day do
        local entry = history[windowDay]
        if entry and entry[item.reference] then values[#values + 1] = entry[item.reference] end
      end
      local point = {day = day, label = Core.DayLabel(day), low = row and row.low,
        high = row and row.high, maxAvailable = row and row.maxAvailable,
        median7 = #values >= 3 and Core.Median(values) or nil}
      if row and (row.low or row.high) then chart.coverage = chart.coverage + 1 end
      chart.days[#chart.days + 1] = point
    end
    view.charts[#view.charts + 1] = chart
  end
  local crystal, thorium, arcanite = stored.latest[12363], stored.latest[12359], stored.latest[12360]
  if crystal and thorium and arcanite and crystal.day == thorium.day and thorium.day == arcanite.day
    and arcanite.day <= today then
    local cost = crystal.price + thorium.price
    local net = Core.Net(arcanite.price)
    view.quote = {day = arcanite.day, cost = cost, net = net, profit = net - cost}
  end
  for day = today, startDay, -1 do
    local c, t, a = stored.daily[12363][day], stored.daily[12359][day], stored.daily[12360][day]
    if c and t and a and c.low and c.high and t.low and t.high and a.low and a.high then
      view.spread = {day = day, conservative = Core.Net(a.low) - c.high - t.high,
        optimistic = Core.Net(a.high) - c.low - t.low}
      break
    end
  end
  return view
end
