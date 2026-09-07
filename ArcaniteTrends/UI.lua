local _, A = ...

-- The display only reads the companion's retained data. All Auctionator access
-- stays in the adapter so resizing or hovering never starts work in the AH.
A.UI = {}
local UI = A.UI
local window, minimapButton
local charts = {}
local WHITE = { 0.91, 0.93, 0.95 }
local MUTED = { 0.62, 0.68, 0.73 }
local GOLD = { 0.92, 0.72, 0.32 }
local MEDIAN = { 0.39, 0.86, 0.73 }
local ITEM_COLORS = {
  [12363] = { 0.72, 0.61, 0.96 },
  [12359] = { 0.63, 0.76, 0.86 },
  [12360] = GOLD,
}
local unpack = unpack or table.unpack

local function finite(value)
  return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function clamp(value, low, high)
  return math.max(low, math.min(high, value))
end

local function preferences()
  A.db.ui = type(A.db.ui) == "table" and A.db.ui or {}
  return A.db.ui
end

local function font(parent, size, color, flags)
  local text = parent:CreateFontString(nil, "OVERLAY")
  text:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, flags or "")
  text:SetTextColor(unpack(color or WHITE))
  text:SetJustifyH("LEFT")
  return text
end

local function backdrop(frame, background, border)
  frame:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
  })
  frame:SetBackdropColor(unpack(background))
  frame:SetBackdropBorderColor(unpack(border))
end

local function newLine(parent, color, thickness)
  local line = parent:CreateLine(nil, "ARTWORK")
  line:SetColorTexture(unpack(color))
  line:SetThickness(thickness or 1)
  return line
end

local function lineAt(line, parent, x1, y1, x2, y2)
  line:SetStartPoint("BOTTOMLEFT", parent, x1, y1)
  line:SetEndPoint("BOTTOMLEFT", parent, x2, y2)
  line:Show()
end

local function money(value, signed)
  if not finite(value) then return "Unavailable" end
  return A.Core.FormatCopper(value, signed)
end

local function dateText(day)
  return finite(day) and A.Core.DateString(day) or "Unknown date"
end

local function axisMoney(value)
  if value >= 10000 then return string.format("%.1fg", value / 10000) end
  if value >= 100 then return string.format("%.1fs", value / 100) end
  return string.format("%.0fc", value)
end

local function addPriceTooltip(label, value)
  GameTooltip:AddDoubleLine(label, money(value), unpack(MUTED))
end

local function showDayTooltip(hit)
  local chart = hit.chart
  local record = chart.data and chart.data.days[hit.index]
  if not record then return end
  GameTooltip:SetOwner(hit, "ANCHOR_RIGHT")
  GameTooltip:AddLine(chart.data.name .. " - " .. dateText(record.day), unpack(WHITE))
  if finite(record.low) or finite(record.high) then
    addPriceTooltip("Daily low minimum buyout", record.low)
    addPriceTooltip("Daily high minimum buyout", record.high)
    addPriceTooltip("7-day median of daily " .. (chart.data.reference == "high" and "highs" or "lows"), record.median7)
    GameTooltip:AddDoubleLine("Maximum availability", finite(record.maxAvailable) and tostring(record.maxAvailable) or "Unknown", unpack(MUTED))
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("The daily range contains observed minimum buyouts from potentially different scans.", 0.76, 0.78, 0.81, true)
    GameTooltip:AddLine("Quantity is scan-sensitive maximum availability.", 0.76, 0.78, 0.81, true)
  else
    GameTooltip:AddLine("No recorded price for this date.", unpack(MUTED))
    GameTooltip:AddLine("Missing dates remain gaps; listings may still have existed.", 0.76, 0.78, 0.81, true)
  end
  GameTooltip:Show()
end

local function createChart(parent)
  local chart = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  backdrop(chart, { 0.055, 0.078, 0.095, 1 }, { 0.16, 0.21, 0.25, 1 })
  chart.title = font(chart, 13, WHITE, "OUTLINE")
  chart.title:SetPoint("TOPLEFT", 12, -10)
  chart.latest = font(chart, 13, WHITE)
  chart.latest:SetPoint("TOPRIGHT", -12, -10)
  chart.latest:SetJustifyH("RIGHT")
  chart.legend = font(chart, 10, MUTED)
  chart.legend:SetPoint("TOPLEFT", 12, -29)
  chart.coverage = font(chart, 10, MUTED)
  chart.coverage:SetPoint("TOPRIGHT", -12, -29)
  chart.coverage:SetJustifyH("RIGHT")
  chart.plot = CreateFrame("Frame", nil, chart)
  chart.plot:SetPoint("TOPLEFT", 64, -49)
  chart.plot:SetPoint("BOTTOMRIGHT", -15, 24)
  chart.grids, chart.yLabels, chart.xLabels, chart.bars, chart.segments, chart.hits = {}, {}, {}, {}, {}, {}
  for index = 1, 3 do
    chart.grids[index] = newLine(chart.plot, { 0.18, 0.24, 0.29, 0.75 })
    chart.yLabels[index] = font(chart.plot, 9, MUTED)
    chart.yLabels[index]:SetJustifyH("RIGHT")
    chart.yLabels[index]:SetWidth(56)
  end
  for index = 1, 5 do
    chart.xLabels[index] = font(chart.plot, 9, MUTED)
    chart.xLabels[index]:SetJustifyH("CENTER")
    chart.xLabels[index]:SetWidth(64)
  end
  for index = 1, 30 do
    chart.bars[index] = {
      range = newLine(chart.plot, GOLD, 2),
      lowCap = newLine(chart.plot, GOLD, 1),
      highCap = newLine(chart.plot, GOLD, 1),
      reference = chart.plot:CreateTexture(nil, "OVERLAY"),
      medianMark = chart.plot:CreateTexture(nil, "OVERLAY"),
    }
    chart.bars[index].reference:SetSize(4, 4)
    chart.bars[index].medianMark:SetSize(4, 4)
    chart.bars[index].medianMark:SetColorTexture(unpack(MEDIAN))
    chart.segments[index] = newLine(chart.plot, MEDIAN, 2)
    local hit = CreateFrame("Frame", nil, chart.plot)
    hit:EnableMouse(true)
    hit.chart, hit.index = chart, index
    hit:SetScript("OnEnter", showDayTooltip)
    hit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    chart.hits[index] = hit
  end
  chart.empty = font(chart.plot, 11, MUTED)
  chart.empty:SetPoint("CENTER")
  chart.empty:SetText("No recorded prices in these 30 days")
  return chart
end

local function drawChart(chart, data)
  chart.data = data
  if not data then chart:Hide(); return end
  chart:Show()
  local color = ITEM_COLORS[data.itemId] or GOLD
  chart.title:SetText(data.name)
  chart.title:SetTextColor(unpack(color))
  chart.title:SetWidth(chart:GetWidth() * 0.38)
  chart.latest:SetWidth(chart:GetWidth() * 0.58)
  chart.latest:SetText(data.latest and (money(data.latest.price) .. "  |  " .. dateText(data.latest.day)) or "No last-seen price")
  chart.legend:SetText("Daily low-high  |  |cff64dbba7d median of daily " .. (data.reference == "high" and "highs" or "lows") .. "|r")
  chart.coverage:SetText(tostring(data.coverage or 0) .. " / 30 days observed")

  local low, high
  for _, record in ipairs(data.days) do
    for _, key in ipairs({ "low", "high", "median7" }) do
      local value = record[key]
      if finite(value) and (key ~= "median7" or finite(record[data.reference])) then
        low = low and math.min(low, value) or value
        high = high and math.max(high, value) or value
      end
    end
  end
  chart.empty:SetShown(low == nil)
  low, high = low or 0, high or 10000
  local padding = math.max((high - low) * 0.15, high * 0.015, 1)
  low, high = math.max(0, low - padding), high + padding
  local width, height = math.max(1, chart.plot:GetWidth()), math.max(1, chart.plot:GetHeight())
  local slot = width / 30
  local function y(value) return (value - low) / (high - low) * height end
  for index = 1, 3 do
    local fraction = (index - 1) / 2
    lineAt(chart.grids[index], chart.plot, 0, fraction * height, width, fraction * height)
    chart.yLabels[index]:ClearAllPoints()
    chart.yLabels[index]:SetPoint("RIGHT", chart.plot, "BOTTOMLEFT", -7, fraction * height)
    chart.yLabels[index]:SetText(axisMoney(low + fraction * (high - low)))
  end
  for index, position in ipairs({ 1, 8, 15, 22, 30 }) do
    chart.xLabels[index]:ClearAllPoints()
    chart.xLabels[index]:SetPoint("TOP", chart.plot, "BOTTOMLEFT", (position - 0.5) * slot, -5)
    local record = data.days[position]
    chart.xLabels[index]:SetText(record and (record.label or A.Core.DayLabel(record.day)) or "")
  end

  for index = 1, 30 do
    local record = data.days[index]
    local bar, segment, hit = chart.bars[index], chart.segments[index], chart.hits[index]
    bar.range:Hide(); bar.lowCap:Hide(); bar.highCap:Hide(); bar.reference:Hide(); bar.medianMark:Hide(); segment:Hide()
    hit:ClearAllPoints()
    hit:SetPoint("BOTTOMLEFT", chart.plot, "BOTTOMLEFT", (index - 1) * slot, 0)
    hit:SetSize(slot, height)
    hit:SetShown(record ~= nil)
    if record then
      local x = (index - 0.5) * slot
      local cap = math.min(4, slot * 0.32)
      for _, line in ipairs({ bar.range, bar.lowCap, bar.highCap }) do line:SetColorTexture(unpack(color)) end
      bar.reference:SetColorTexture(unpack(color))
      if finite(record.low) and finite(record.high) then
        lineAt(bar.range, chart.plot, x, y(record.low), x, y(record.high))
      end
      if finite(record.low) then lineAt(bar.lowCap, chart.plot, x - cap, y(record.low), x + cap, y(record.low)) end
      if finite(record.high) then lineAt(bar.highCap, chart.plot, x - cap, y(record.high), x + cap, y(record.high)) end
      local reference = record[data.reference]
      if finite(reference) then
        bar.reference:ClearAllPoints()
        bar.reference:SetPoint("CENTER", chart.plot, "BOTTOMLEFT", x, y(reference))
        bar.reference:Show()
        if finite(record.median7) then
          bar.medianMark:ClearAllPoints()
          bar.medianMark:SetPoint("CENTER", chart.plot, "BOTTOMLEFT", x, y(record.median7))
          bar.medianMark:Show()
        end
      end
      local previous = data.days[index - 1]
      -- Both calendar slots must have observations. Never bridge an empty day.
      if previous and finite(reference) and finite(previous[data.reference]) and finite(record.median7) and finite(previous.median7) and previous.day + 1 == record.day then
        lineAt(segment, chart.plot, x - slot, y(previous.median7), x, y(record.median7))
      end
    end
  end
end

local function saveGeometry()
  if not window or not A.db then return end
  local ui = preferences()
  ui.width, ui.height = window:GetWidth(), window:GetHeight()
  local x, y = window:GetCenter()
  local parentX, parentY = UIParent:GetCenter()
  if finite(x) and finite(y) and finite(parentX) and finite(parentY) then
    local scale = window:GetScale()
    ui.x, ui.y = x - parentX / scale, y - parentY / scale
  end
end

local function layout()
  if not window then return end
  local width, height = window:GetWidth(), window:GetHeight()
  window.source:SetWidth(width - 40)
  window.subtitle:SetWidth(width - 80)
  local chartHeight = (height - 304) / 3
  for index, chart in ipairs(charts) do
    chart:ClearAllPoints()
    chart:SetPoint("TOPLEFT", window, "TOPLEFT", 18, -108 - (index - 1) * (chartHeight + 10))
    chart:SetSize(width - 36, chartHeight)
    if window.view then drawChart(chart, window.view.charts[index]) end
  end
  window.footer:SetSize(width - 36, 150)
  window.footer:SetPoint("BOTTOMLEFT", 18, 14)
  for _, field in ipairs({ "quote", "spread", "caveat", "deposit" }) do
    window[field]:SetWidth(width - 62)
  end
end

local function sourceText()
  local runtime = A.runtime or {}
  local message = runtime.message or "Waiting for Auctionator's database."
  local checked = window.view and window.view.lastSyncedAt
  if finite(checked) and checked > 0 then
    message = message .. "  |  Last checked " .. date("%b %d, %H:%M", checked)
  end
  window.source:SetText(message)
  local state = runtime.state
  if state == "error" or state == "unsupported" or state == "timeout" then
    window.source:SetTextColor(1, 0.61, 0.45)
  elseif state == "paused" or state == "waiting" or state == "warning" then
    window.source:SetTextColor(unpack(GOLD))
  else
    window.source:SetTextColor(unpack(MUTED))
  end
end

function UI.Refresh()
  if not window or not A.db then return end
  local today = A.Adapter.Today()
  window.view = A.Core.BuildView(A.db, today)
  sourceText()
  window.subtitle:SetText("Mankrik Alliance  |  Auctionator observations  |  " .. dateText(window.view.startDay) .. " to " .. dateText(window.view.today))
  local quote = window.view.quote
  if quote then
    window.quote:SetText("Last-seen prices (" .. dateText(quote.day) .. "):  Reagents " .. money(quote.cost) .. "  |  Net sale " .. money(quote.net) .. "\nIndicative margin: |cffeac052" .. money(quote.profit, true) .. "|r")
  else
    window.quote:SetText("Indicative margin unavailable: all three last-seen prices must share a recorded date.")
  end
  local spread = window.view.spread
  if spread then
    window.spread:SetText("Daily scenarios (" .. dateText(spread.day) .. "):  Conservative " .. money(spread.conservative, true) .. "  |  Optimistic " .. money(spread.optimistic, true))
  else
    window.spread:SetText("Daily scenarios unavailable: no complete three-item date in this period.")
  end
  layout()
end

local function toggle()
  if not window then return end
  window:SetShown(not window:IsShown())
end

local function minimapPosition(angle)
  local radius = math.max(Minimap:GetWidth(), Minimap:GetHeight()) / 2 + 8
  minimapButton:ClearAllPoints()
  minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function cursorAngle()
  local x, y = GetCursorPosition()
  local centerX, centerY = Minimap:GetCenter()
  local scale = Minimap:GetEffectiveScale()
  x, y = x / scale - centerX, y / scale - centerY
  if x > 0 then return math.atan(y / x) end
  if x < 0 then return math.atan(y / x) + (y >= 0 and math.pi or -math.pi) end
  return y >= 0 and math.pi / 2 or -math.pi / 2
end

local function createMinimapButton()
  minimapButton = CreateFrame("Button", "ArcaniteTrendsMinimapButton", Minimap)
  minimapButton:SetSize(31, 31)
  minimapButton:SetFrameStrata("MEDIUM")
  minimapButton:SetFrameLevel(Minimap:GetFrameLevel() + 8)
  minimapButton:RegisterForClicks("LeftButtonUp")
  minimapButton:RegisterForDrag("LeftButton")
  minimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
  local icon = minimapButton:CreateTexture(nil, "BACKGROUND")
  icon:SetTexture("Interface\\Icons\\INV_Misc_Gem_Crystal_02")
  icon:SetSize(20, 20)
  icon:SetPoint("TOPLEFT", 7, -5)
  local border = minimapButton:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetSize(54, 54)
  border:SetPoint("TOPLEFT")
  local ui = preferences()
  minimapPosition(finite(ui.minimapAngle) and ui.minimapAngle or math.pi * 1.25)
  minimapButton:SetScript("OnClick", function(self)
    if self.didDrag then self.didDrag = nil; return end
    toggle()
  end)
  minimapButton:SetScript("OnDragStart", function(self)
    self.didDrag = true
    GameTooltip:Hide()
    self:SetScript("OnUpdate", function()
      local angle = cursorAngle()
      preferences().minimapAngle = angle
      minimapPosition(angle)
    end)
  end)
  minimapButton:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
    -- OnClick can follow drag-stop on some clients. Clear the guard next frame.
    C_Timer.After(0, function() self.didDrag = nil end)
  end)
  minimapButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("ArcaniteTrends", unpack(GOLD))
    GameTooltip:AddLine("Click to view 30 days of Auctionator history.", 0.91, 0.93, 0.95, true)
    GameTooltip:AddLine("Drag to reposition. You can also type /arc.", unpack(MUTED))
    GameTooltip:Show()
  end)
  minimapButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function UI.Initialize()
  if window or not A.db then return end
  local ui = preferences()
  window = CreateFrame("Frame", "ArcaniteTrendsWindow", UIParent, "BackdropTemplate")
  window:Hide()
  window:SetFrameStrata("DIALOG")
  window:SetMovable(true)
  window:SetResizable(true)
  window:SetClampedToScreen(true)
  window:EnableMouse(true)
  backdrop(window, { 0.025, 0.036, 0.047, 0.98 }, { 0.42, 0.34, 0.18, 1 })
  local availableWidth, availableHeight = math.max(1, UIParent:GetWidth() - 30), math.max(1, UIParent:GetHeight() - 30)
  local scale = math.min(1, availableWidth / 620, availableHeight / 650)
  window:SetScale(scale)
  local maxWidth, maxHeight = availableWidth / scale, availableHeight / scale
  local minWidth, minHeight = 620, 650
  window:SetResizeBounds(minWidth, minHeight, maxWidth, maxHeight)
  window:SetSize(clamp(finite(ui.width) and ui.width or 840, minWidth, maxWidth), clamp(finite(ui.height) and ui.height or 800, minHeight, maxHeight))
  local x = clamp(finite(ui.x) and ui.x or 0, -(maxWidth - window:GetWidth()) / 2, (maxWidth - window:GetWidth()) / 2)
  local y = clamp(finite(ui.y) and ui.y or 0, -(maxHeight - window:GetHeight()) / 2, (maxHeight - window:GetHeight()) / 2)
  window:SetPoint("CENTER", UIParent, "CENTER", x, y)

  local title = font(window, 22, GOLD, "OUTLINE")
  title:SetPoint("TOPLEFT", 18, -15)
  title:SetText("Arcanite Trends")
  window.subtitle = font(window, 10, MUTED)
  window.subtitle:SetPoint("TOPLEFT", 20, -44)
  window.source = font(window, 11, MUTED)
  window.source:SetPoint("TOPLEFT", 20, -64)
  window.source:SetHeight(35)
  window.source:SetJustifyV("TOP")

  local drag = CreateFrame("Frame", nil, window)
  drag:SetPoint("TOPLEFT")
  drag:SetPoint("TOPRIGHT", -38, 0)
  drag:SetHeight(58)
  drag:EnableMouse(true)
  drag:RegisterForDrag("LeftButton")
  drag:SetScript("OnDragStart", function() window:StartMoving() end)
  drag:SetScript("OnDragStop", function() window:StopMovingOrSizing(); saveGeometry() end)
  local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -3, -3)
  close:SetScript("OnClick", function() window:Hide() end)
  for index = 1, 3 do charts[index] = createChart(window) end

  window.footer = CreateFrame("Frame", nil, window, "BackdropTemplate")
  backdrop(window.footer, { 0.06, 0.073, 0.084, 1 }, { 0.20, 0.23, 0.24, 1 })
  window.quote = font(window.footer, 11, WHITE)
  window.quote:SetPoint("TOPLEFT", 12, -10)
  window.quote:SetHeight(33)
  window.quote:SetJustifyV("TOP")
  window.spread = font(window.footer, 11, WHITE)
  window.spread:SetPoint("TOPLEFT", 12, -48)
  window.spread:SetHeight(28)
  window.spread:SetJustifyV("TOP")
  window.caveat = font(window.footer, 10, MUTED)
  window.caveat:SetPoint("TOPLEFT", 12, -80)
  window.caveat:SetHeight(30)
  window.caveat:SetJustifyV("TOP")
  window.caveat:SetText("Recorded days do not imply synchronized scans. Daily extrema may have occurred at different times; margins and scenarios are indicative listing opportunities.")
  window.deposit = font(window.footer, 10, GOLD)
  window.deposit:SetPoint("TOPLEFT", 12, -116)
  window.deposit:SetHeight(24)
  window.deposit:SetJustifyV("TOP")
  window.deposit:SetText("5% AH cut included. 30s deposit held for a 24h sale; returned on success, not deducted.")

  local resize = CreateFrame("Button", nil, window)
  resize:SetSize(18, 18)
  resize:SetPoint("BOTTOMRIGHT", -1, 1)
  resize:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  resize:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  resize:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  resize:SetScript("OnMouseDown", function(_, button) if button == "LeftButton" then window:StartSizing("BOTTOMRIGHT") end end)
  resize:SetScript("OnMouseUp", function() window:StopMovingOrSizing(); saveGeometry() end)
  window:SetScript("OnSizeChanged", layout)
  window:SetScript("OnShow", function()
    UI.Refresh()
    if A.RequestRefresh then A.RequestRefresh("open") end
  end)
  window:SetScript("OnHide", function()
    window:StopMovingOrSizing()
    GameTooltip:Hide()
    saveGeometry()
  end)
  UISpecialFrames = UISpecialFrames or {}
  table.insert(UISpecialFrames, "ArcaniteTrendsWindow")
  SlashCmdList.ARCANITETRENDS = toggle
  SLASH_ARCANITETRENDS1 = "/arc"
  createMinimapButton()
  UI.Refresh()
end
