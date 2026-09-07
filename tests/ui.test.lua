local function loadFull()
  Mock.Reset()
  for _, name in ipairs({ "Core.lua", "SeedData.lua", "AuctionatorAdapter.lua", "UI.lua", "Main.lua" }) do
    LoadAddonFile(name)
  end
end
local function initialize()
  Mock.Event("ADDON_LOADED", "ArcaniteTrends")
  Mock.Event("PLAYER_LOGIN")
  Mock.Advance(1)
end
local function charts()
  local result = {}
  for _, frame in ipairs(Mock.frames) do if rawget(frame, "bars") then result[#result + 1] = frame end end
  return result
end

Test("Main waits for addon load and player login; display starts hidden", function()
  loadFull()
  Mock.loaded = false
  Mock.Event("ADDON_LOADED", "UnrelatedAddon")
  Equal(A.db, nil)
  Mock.Event("ADDON_LOADED", "ArcaniteTrends")
  Truth(A.db)
  Equal(ArcaniteTrendsWindow:IsShown(), false)
  Truth(ArcaniteTrendsMinimapButton:IsShown())
  Equal(Mock.registrationCount, 0)
  Mock.Event("PLAYER_LOGIN") Mock.Advance(1)
  Equal(Mock.registrationCount, 1)
  Equal(ArcaniteTrendsWindow:IsShown(), false)
  Equal(SLASH_ARCANITETRENDS1, "/arc")
  Equal(UISpecialFrames[1], "ArcaniteTrendsWindow")
end)

Test("slash and minimap toggle the window without automatic opening after scans", function()
  loadFull() initialize()
  SlashCmdList.ARCANITETRENDS()
  Truth(ArcaniteTrendsWindow:IsShown())
  ArcaniteTrendsMinimapButton:Click()
  Equal(ArcaniteTrendsWindow:IsShown(), false)
  Mock.SetItem(12363, A.Adapter.Today(), 919994, 930000)
  Mock.Notify() Mock.Advance(1)
  Equal(ArcaniteTrendsWindow:IsShown(), false)
  ArcaniteTrendsMinimapButton:Click()
  Truth(ArcaniteTrendsWindow:IsShown())
  Contains(ArcaniteTrendsWindow.subtitle:GetText(), "Mankrik Alliance")
end)

Test("charts show ranges, correct median references, honest gaps and recorded dates", function()
  loadFull()
  local today = A.Adapter.Today()
  Mock.SetItem(12363, today, 919994, 930000, 4)
  Mock.SetItem(12359, today, 2425, 3000, 50)
  Mock.SetItem(12360, today, 1112200, 1200000, 5)
  initialize()
  local all = charts()
  Equal(#all, 3)
  Equal(all[1].data.itemId, 12363) Equal(all[2].data.itemId, 12359) Equal(all[3].data.itemId, 12360)
  Contains(all[1].legend:GetText(), "lows") Contains(all[3].legend:GetText(), "highs")
  Contains(all[1].latest:GetText(), A.Core.DateString(today))
  Contains(all[1].coverage:GetText(), "1 / 30")
  Equal(all[1].bars[29].range:IsShown(), false)
  Equal(all[1].bars[30].range:IsShown(), true)
  Contains(ArcaniteTrendsWindow.quote:GetText(), "+13g 41s 71c")
  Contains(ArcaniteTrendsWindow.spread:GetText(), "Conservative")
  Contains(ArcaniteTrendsWindow.spread:GetText(), "Optimistic")
  Contains(ArcaniteTrendsWindow.caveat:GetText(), "different times")
  Contains(ArcaniteTrendsWindow.deposit:GetText(), "30s")
end)

Test("tooltips explain observed ranges, scan-sensitive quantity and missing days", function()
  loadFull()
  Mock.SetItem(12363, A.Adapter.Today(), 919994, 930000, 4)
  initialize()
  local chart = charts()[1]
  chart.hits[30]:GetScript("OnEnter")(chart.hits[30])
  Truth(GameTooltip:IsShown())
  local content = table.concat(GameTooltip.lines, "\n")
  Contains(content, "Daily low minimum buyout") Contains(content, "Daily high minimum buyout")
  Contains(content, "Maximum availability: 4") Contains(content, "scan-sensitive")
  chart.hits[30]:GetScript("OnLeave")()
  Equal(GameTooltip:IsShown(), false)
  chart.hits[29]:GetScript("OnEnter")(chart.hits[29])
  Contains(table.concat(GameTooltip.lines, "\n"), "No recorded price")
end)

Test("median graph does not bridge an unobserved calendar day", function()
  loadFull() initialize()
  local today = A.Adapter.Today()
  local rows = {}
  for day = today - 6, today do
    if day ~= today - 2 then rows[#rows + 1] = { itemId = 12363, day = day, low = 100, high = 200 } end
  end
  A.Core.MergeRows(A.db, rows) A.UI.Refresh()
  local chart = charts()[1]
  Equal(chart.data.days[28].low, nil)
  Truth(chart.data.days[28].median7, "statistics may exist while raw observation is missing")
  Equal(chart.segments[28]:IsShown(), false)
  Equal(chart.segments[29]:IsShown(), false)
  Truth(chart.segments[30]:IsShown(), "adjacent observed dates can connect")
end)

Test("hidden warm-up medians do not fabricate visible history on an empty chart", function()
  loadFull() initialize()
  local today = A.Adapter.Today()
  A.Core.MergeRows(A.db, {
    { itemId = 12363, day = today - 35, low = 100, high = 200 },
    { itemId = 12363, day = today - 34, low = 110, high = 210 },
    { itemId = 12363, day = today - 30, low = 120, high = 220 },
  })
  A.UI.Refresh()
  local chart = charts()[1]
  Equal(chart.data.coverage, 0)
  Truth(chart.data.days[1].median7)
  Truth(chart.empty:IsShown())
  for index = 1, 30 do
    Equal(chart.bars[index].range:IsShown(), false)
    Equal(chart.segments[index]:IsShown(), false)
  end
end)

Test("small UI parent scales the minimum window to fit and keeps plot dimensions positive", function()
  loadFull()
  UIParent:SetSize(500, 400)
  initialize()
  Truth(ArcaniteTrendsWindow:GetScale() < 1)
  Truth(ArcaniteTrendsWindow:GetWidth() * ArcaniteTrendsWindow:GetScale() <= 470)
  Truth(ArcaniteTrendsWindow:GetHeight() * ArcaniteTrendsWindow:GetScale() <= 370)
  for _, chart in ipairs(charts()) do Truth(chart:GetWidth() > 0) Truth(chart:GetHeight() > 0) end
end)

Test("redrawing and resizing reuse graph objects and preserve geometry preferences", function()
  loadFull() initialize()
  SlashCmdList.ARCANITETRENDS()
  local count = #Mock.frames
  for _ = 1, 5 do A.UI.Refresh() end
  ArcaniteTrendsWindow:SetSize(700, 680)
  Equal(#Mock.frames, count)
  ArcaniteTrendsWindow:Hide()
  Equal(A.db.ui.width, 700) Equal(A.db.ui.height, 680)
  Equal(GameTooltip:IsShown(), false)
  Equal(ArcaniteTrendsWindow:GetScript("OnUpdate"), nil)
  Equal(ArcaniteTrendsMinimapButton:GetScript("OnUpdate"), nil)
  local before = #Mock.frames
  A.UI.Initialize()
  Equal(#Mock.frames, before, "repeated initialization should be harmless")
end)

Test("display error and paused states retain the available chart history", function()
  loadFull()
  Mock.SetItem(12363, A.Adapter.Today(), 919994, 930000)
  initialize()
  Auctionator.Database.GetPriceHistory = nil
  A.RequestRefresh("open") Mock.Advance(1)
  Equal(A.runtime.state, "error")
  Contains(ArcaniteTrendsWindow.source:GetText(), "interface changed")
  Equal(charts()[1].data.coverage, 1)
  Mock.realm = "Pagle"
  A.RequestRefresh("open") Mock.Advance(1)
  Equal(A.runtime.state, "paused")
  Contains(ArcaniteTrendsWindow.source:GetText(), "paused")
  Equal(charts()[1].data.coverage, 1)
end)

Test("future SavedVariables schema stays untouched and prevents background capture", function()
  loadFull()
  local future = { schemaVersion = 99, privateSentinel = "synthetic" }
  ArcaniteTrendsDB = future
  initialize()
  Equal(ArcaniteTrendsDB, future)
  Equal(future.privateSentinel, "synthetic")
  Equal(A.runtime.state, "error") Equal(Mock.registrationCount, 0) Equal(Mock.readCount, 0)
  A.RequestRefresh("open") Mock.Advance(1)
  Equal(Mock.readCount, 0)
  Contains(ArcaniteTrendsWindow.source:GetText(), "unsupported")
end)
