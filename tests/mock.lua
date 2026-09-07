local total, failures = 0, {}
function Test(name, fn)
  total = total + 1
  local ok, message = pcall(fn)
  if ok then print("PASS " .. name) else
    failures[#failures + 1] = name .. ": " .. tostring(message)
    print("FAIL " .. failures[#failures])
  end
end
function Equal(actual, expected, context)
  assert(actual == expected, (context or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
function Truth(value, context) assert(value, context or "expected truthy value") end
function Contains(value, text) assert(type(value) == "string" and value:find(text, 1, true), tostring(value) .. " does not contain " .. text) end
function FinishTests()
  print(tostring(total - #failures) .. "/" .. tostring(total) .. " synthetic addon checks passed")
  if #failures > 0 then error(table.concat(failures, "\n")) end
end
function LoadAddonFile(name)
  local code = assert(__addonSources[name], "Missing addon file: " .. name)
  local chunk = assert(load(code, "@ArcaniteTrends/" .. name))
  return chunk("ArcaniteTrends", A)
end

-- Deterministic timers let tests model Auctionator's early notification without
-- calling WoW or waiting in real time. Time is synthetic, never player history.
Mock = {}
function Mock.Reset()
  A = {}
  ArcaniteTrendsDB = nil
  Mock.clock, Mock.epoch, Mock.timers = 0, 1700000000, {}
  Mock.frames, Mock.named, Mock.messages = {}, {}, {}
  Mock.callbacks, Mock.registrationCount = {}, 0
  Mock.history, Mock.prices, Mock.readCount = {}, {}, 0
  Mock.realm, Mock.faction = "Mankrik", "Alliance"
  Mock.loaded = true
  time = function(calendar) return calendar and 1577836800 or Mock.epoch + Mock.clock end
  GetServerTime = time
  GetTime = function() return Mock.clock end
  GetRealmName = function() return Mock.realm end
  GetNormalizedRealmName = GetRealmName
  UnitFactionGroup = function() return Mock.faction end
  UnitName = function() return "SyntheticPlayer" end
  GetLocale = function() return "enUS" end
  GetBuildInfo = function() return "1.15.9", "12345", "test", 11509 end
  GetCursorPosition = function() return 100, 100 end
  IsLoggedIn = function() return Mock.loaded end
  GetItemIcon = function(id) return id end
  C_Item = { GetItemIconByID = GetItemIcon }
  IsAddOnLoaded = function() return true end
  C_AddOns = { IsAddOnLoaded = IsAddOnLoaded }
  SlashCmdList, UISpecialFrames = {}, {}
  DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) Mock.messages[#Mock.messages + 1] = msg end }
  C_Timer = {}
  function C_Timer.After(delay, fn)
    Mock.timers[#Mock.timers + 1] = { at = Mock.clock + delay, fn = fn }
  end
  function C_Timer.NewTimer(delay, fn)
    local handle = { cancelled = false }
    function handle:Cancel() self.cancelled = true end
    function handle:IsCancelled() return self.cancelled end
    C_Timer.After(delay, function() if not handle.cancelled then fn(handle) end end)
    return handle
  end
  local frameMethods = {}
  local function region(kind, name, parent)
    local object = { kind = kind, name = name, parent = parent, shown = true,
      width = 900, height = 760, scripts = {}, points = {}, text = "", lines = {}, children = {} }
    local function remember(self, ...) self.lastArgs = { ... } end
    setmetatable(object, { __index = function(_, key)
      return frameMethods[key] or (type(key) == "string" and key:match("^[A-Z]") and remember or nil)
    end })
    Mock.frames[#Mock.frames + 1] = object
    if name then Mock.named[name], _G[name] = object, object end
    if parent and parent.children then parent.children[#parent.children + 1] = object end
    return object
  end
  function frameMethods:SetScript(name, fn) self.scripts[name] = fn end
  function frameMethods:GetScript(name) return self.scripts[name] end
  function frameMethods:HookScript(name, fn)
    local old = self.scripts[name]
    self.scripts[name] = function(...) if old then old(...) end fn(...) end
  end
  function frameMethods:RegisterEvent(event) self.events = self.events or {} self.events[event] = true end
  function frameMethods:UnregisterEvent(event) if self.events then self.events[event] = nil end end
  function frameMethods:SetSize(w, h)
    self.width, self.height = w, h
    if self.scripts.OnSizeChanged then self.scripts.OnSizeChanged(self, w, h) end
  end
  function frameMethods:SetWidth(w) self.width = w end
  function frameMethods:SetHeight(h) self.height = h end
  function frameMethods:GetSize() return self.width, self.height end
  function frameMethods:GetWidth() return self.width end
  function frameMethods:GetHeight() return self.height end
  function frameMethods:Show()
    local changed = not self.shown self.shown = true
    if changed and self.scripts.OnShow then self.scripts.OnShow(self) end
  end
  function frameMethods:Hide()
    local changed = self.shown self.shown = false
    if changed and self.scripts.OnHide then self.scripts.OnHide(self) end
  end
  function frameMethods:IsShown() return self.shown end
  function frameMethods:SetShown(shown) if shown then self:Show() else self:Hide() end end
  function frameMethods:IsVisible() return self.shown end
  function frameMethods:GetName() return self.name end
  function frameMethods:GetParent() return self.parent end
  function frameMethods:SetPoint(...) self.points[#self.points + 1] = { ... } end
  function frameMethods:ClearAllPoints() self.points = {} end
  function frameMethods:GetPoint() return table.unpack(self.points[1] or { "CENTER", nil, "CENTER", 0, 0 }) end
  function frameMethods:GetCenter() return 0, 0 end
  function frameMethods:GetEffectiveScale() return 1 end
  function frameMethods:SetScale(scale) self.scale = scale end
  function frameMethods:GetScale() return rawget(self, "scale") or 1 end
  function frameMethods:GetFrameLevel() return 1 end
  function frameMethods:GetLeft() return 0 end
  function frameMethods:GetBottom() return 0 end
  function frameMethods:SetText(value) self.text = value end
  function frameMethods:GetText() return self.text end
  function frameMethods:SetFormattedText(format, ...) self.text = string.format(format, ...) end
  function frameMethods:GetStringWidth() return #tostring(self.text) * 6 end
  function frameMethods:GetStringHeight() return 14 end
  function frameMethods:CreateFontString(name) return region("FontString", name, self) end
  function frameMethods:CreateTexture(name) return region("Texture", name, self) end
  function frameMethods:CreateLine(name) return region("Line", name, self) end
  function frameMethods:GetNormalTexture() self.normalTexture = self.normalTexture or region("Texture", nil, self) return self.normalTexture end
  function frameMethods:AddLine(text) self.lines[#self.lines + 1] = text end
  function frameMethods:AddDoubleLine(left, right) self.lines[#self.lines + 1] = left .. ": " .. right end
  function frameMethods:ClearLines() self.lines = {} end
  function frameMethods:SetOwner() self.lines = {} end
  function frameMethods:Click(button) if self.scripts.OnClick then self.scripts.OnClick(self, button or "LeftButton") end end
  CreateFrame = function(kind, name, parent) return region(kind, name, parent) end
  UIParent = CreateFrame("Frame", "UIParent")
  Minimap = CreateFrame("Frame", "Minimap", UIParent)
  GameTooltip = CreateFrame("GameTooltip", "GameTooltip", UIParent)
  GameTooltip:Hide()
  math.atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
  math.mod = math.mod or math.fmod
  unpack = table.unpack
  wipe = function(t) for key in pairs(t) do t[key] = nil end return t end
  tinsert, tremove = table.insert, table.remove
  date = function(format) return format == "%Y-%m-%d" and "2023-11-14" or "mock date" end
  Auctionator = {
    Constants = { SCAN_DAY_0 = 1577836800 },
    Variables = { GetConnectedRealmRoot = function() return Mock.realm end },
    Database = {}, API = { v1 = {} },
  }
  function Auctionator.Database:GetPriceHistory(key)
    Mock.readCount = Mock.readCount + 1
    return Mock.history[tonumber(key)] or {}
  end
  function Auctionator.API.v1.GetAuctionPriceByItemID(_, id) return Mock.prices[id] end
  function Auctionator.API.v1.RegisterForDBUpdate(_, callback)
    Mock.registrationCount = Mock.registrationCount + 1
    Mock.callbacks[#Mock.callbacks + 1] = callback
  end
end
function Mock.Advance(seconds)
  local target, count = Mock.clock + seconds, 0
  while true do
    local index, earliest
    for i, timer in ipairs(Mock.timers) do
      if timer.at <= target and (not earliest or timer.at < earliest) then index, earliest = i, timer.at end
    end
    if not index then break end
    local timer = table.remove(Mock.timers, index)
    Mock.clock = timer.at
    timer.fn()
    count = count + 1 assert(count < 10000, "runaway timer loop")
  end
  Mock.clock = target
end
function Mock.Notify() for _, fn in ipairs(Mock.callbacks) do fn() end end
function Mock.Event(event, ...)
  local frames = {} for i, frame in ipairs(Mock.frames) do frames[i] = frame end
  for _, frame in ipairs(frames) do
    if frame.events and frame.events[event] and frame.scripts.OnEvent then frame.scripts.OnEvent(frame, event, ...) end
  end
end
function Mock.SetItem(id, day, low, high, quantity, price)
  Mock.history[id] = {{ rawDay = tostring(day), minSeen = low, maxSeen = high, available = quantity }}
  Mock.prices[id] = price or low
end
function Mock.Copy(value)
  if type(value) ~= "table" then return value end
  local result = {} for key, child in pairs(value) do result[Mock.Copy(key)] = Mock.Copy(child) end return result
end
function Mock.Core()
  Mock.Reset()
  LoadAddonFile("Core.lua")
  ArcaniteTrendsDB = A.Core.InitDB(nil)
  return A.Core, ArcaniteTrendsDB
end
function Mock.Adapter()
  local core, db = Mock.Core()
  A.db = db
  LoadAddonFile("AuctionatorAdapter.lua")
  return A.Adapter, core, db
end
