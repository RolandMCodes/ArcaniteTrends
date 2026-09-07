local function market(db) return db.markets["Mankrik Alliance"] end

Test("adapter decodes raw day strings, high bytes in ignored date text and missing values", function()
  local adapter = Mock.Adapter()
  local rows = adapter.DecodeHistory(12363, {
    { rawDay = "0", date = "localized \195\169\255", minSeen = 100, maxSeen = 150, available = 0 },
    { rawDay = "100", minSeen = 0, maxSeen = 200 },
    { rawDay = "101", minSeen = 0, maxSeen = 0 },
  })
  Equal(#rows, 2)
  table.sort(rows, function(a, b) return a.day < b.day end)
  Equal(rows[1].day, 0) Equal(rows[1].low, 100) Equal(rows[1].maxAvailable, 0)
  Equal(rows[2].low, nil) Equal(rows[2].high, 200)
  Equal(rows[1].date, nil)
end)

Test("adapter rejects malformed history, missing raw days and malformed values", function()
  local adapter = Mock.Adapter()
  for _, history in ipairs({
    "bad", { unexpected = {} }, { { rawDay = "bogus", minSeen = 1, maxSeen = 1 } },
    { { minSeen = 1, maxSeen = 1 } }, { { rawDay = "1", minSeen = 20, maxSeen = 10 } },
    { { rawDay = "1", minSeen = "10", maxSeen = 10 } },
    { { rawDay = "1", minSeen = 10, maxSeen = 10, available = math.huge } },
  }) do Equal(adapter.DecodeHistory(12363, history), nil) end
  Equal(adapter.DecodeHistory(999, {{ rawDay = "1", minSeen = 10, maxSeen = 10 }}), nil)
end)

Test("capture reads only target items and stages the full result before merging", function()
  local adapter, _, db = Mock.Adapter()
  Mock.SetItem(12363, 100, 900, 950, 4, 925)
  Mock.SetItem(12359, 100, 20, 25, 10, 22)
  Mock.SetItem(12360, 100, 1100, 1200, 3, 1150)
  Mock.SetItem(999, 100, 1, 1, 999)
  Truth(adapter.Capture(db)) Equal(Mock.readCount, 3)
  Equal(market(db).latest[12363].day, 100) Equal(market(db).latest[12363].price, 925)
  Equal(market(db).daily[999], nil)
  Mock.SetItem(12363, 101, 800, 900)
  Mock.SetItem(12359, 101, -1, 25)
  Equal(adapter.Capture(db), nil)
  Equal(market(db).daily[12363][101], nil, "failed batch is atomic")
  Equal(market(db).latest[12363].day, 100)
end)

Test("capture rejects unsupported API, database version and uncertain processing", function()
  local adapter, _, db = Mock.Adapter()
  Auctionator.Database.db = { version = 99 }
  local ok, message, state = adapter.Capture(db)
  Equal(ok, nil) Equal(state, "error") Contains(message, "version")
  Auctionator.Database.db = { version = 2 }
  Auctionator.Database.ticker = {}
  ok, message, state = adapter.Capture(db)
  Equal(ok, nil) Equal(state, "error") Contains(message, "processing")
  Auctionator.Database.ticker = nil
  Auctionator.API.v1.GetAuctionPriceByItemID = nil
  ok, message, state = adapter.Capture(db)
  Equal(ok, nil) Equal(state, "error") Contains(message, "interface changed")
end)

Test("API exceptions and future observations preserve the preceding saved state", function()
  local adapter, _, db = Mock.Adapter()
  Mock.SetItem(12363, 100, 900, 950)
  Truth(adapter.Capture(db))
  Mock.SetItem(12363, adapter.Today() + 1, 800, 850)
  local ok, message = adapter.Capture(db)
  Equal(ok, nil) Contains(message, "future")
  Equal(market(db).latest[12363].day, 100)
  Auctionator.Database.GetPriceHistory = function() error("synthetic API failure") end
  Equal(adapter.Capture(db), nil)
  Equal(market(db).daily[12363][100].low, 900)
end)

Test("other realms and factions pause capture without reading their prices", function()
  local adapter, _, db = Mock.Adapter()
  Mock.SetItem(12363, 100, 900, 950)
  Truth(adapter.Capture(db))
  local readCount = Mock.readCount
  for _, identity in ipairs({ {"Mankrik", "Horde"}, {"Pagle", "Alliance"} }) do
    Mock.realm, Mock.faction = identity[1], identity[2]
    local ok, message, state = adapter.Capture(db)
    Equal(ok, nil) Equal(state, "paused") Contains(message, "saved Mankrik")
    Equal(Mock.readCount, readCount)
    Equal(market(db).latest[12363].price, 900)
  end
end)

Test("initialization waits for the database and registers callback once", function()
  local adapter, _, db = Mock.Adapter()
  local database = Auctionator.Database
  Auctionator.Database = nil
  adapter.Start(function() end)
  Mock.Advance(1)
  Equal(A.runtime.state, "waiting") Equal(Mock.registrationCount, 0)
  Auctionator.Database = database
  Mock.SetItem(12363, 100, 900, 950)
  Mock.Advance(1)
  Equal(A.runtime.state, "ready") Equal(Mock.registrationCount, 1)
  Equal(market(db).daily[12363][100].low, 900)
  adapter.Start(function() error("duplicate Start must not replace callback") end)
  adapter.RequestRefresh("open") adapter.RequestRefresh("open")
  Mock.Notify() Mock.Notify() Mock.Advance(1)
  Equal(Mock.registrationCount, 1)
  Equal(#Mock.timers, 0, "no idle polling")
end)

Test("early notification waits until Auctionator's asynchronous processing settles", function()
  local adapter, _, db = Mock.Adapter()
  Mock.SetItem(12363, 100, 900, 950)
  adapter.Start(function() end) Mock.Advance(1)
  Equal(Mock.readCount, 3)
  -- Actual Auctionator may fire its DB notification before creating the ticker.
  Mock.Notify()
  local ticker = { cancelled = false, IsCancelled = function(self) return self.cancelled end }
  Auctionator.Database.ticker = ticker
  C_Timer.After(0.8, function()
    Mock.SetItem(12363, 101, 800, 900, 9, 850)
    ticker.cancelled = true
  end)
  Mock.Advance(0.4)
  Equal(Mock.readCount, 3) Equal(A.runtime.state, "waiting")
  Equal(market(db).latest[12363].day, 100)
  Mock.Advance(1)
  Equal(A.runtime.state, "ready") Equal(Mock.readCount, 6)
  Equal(market(db).latest[12363].day, 101) Equal(market(db).latest[12363].price, 850)
end)

Test("processing timeout retains saved history, stops timers and permits explicit retry", function()
  local adapter, _, db = Mock.Adapter()
  Mock.SetItem(12363, 100, 900, 950)
  adapter.Start(function() end) Mock.Advance(1)
  Auctionator.Database.ticker = { IsCancelled = function() return false end }
  Mock.Notify() Mock.Advance(32)
  Equal(A.runtime.state, "error") Contains(A.runtime.message, "30 seconds")
  Equal(#Mock.timers, 0) Equal(market(db).latest[12363].price, 900)
  Auctionator.Database.ticker = nil
  Mock.SetItem(12363, 101, 800, 900)
  adapter.RequestRefresh("open") Mock.Advance(1)
  Equal(A.runtime.state, "ready") Equal(market(db).latest[12363].day, 101)
  Equal(Mock.registrationCount, 1)
end)

Test("unrelated scans do not refresh an item's recorded observation day", function()
  local adapter, _, db = Mock.Adapter()
  Mock.SetItem(12363, 100, 900, 950)
  adapter.Start(function() end) Mock.Advance(1)
  local synced = db.lastSyncedAt
  Mock.Advance(10) Mock.SetItem(999, adapter.Today(), 1, 1)
  Mock.Notify() Mock.Advance(1)
  Truth(db.lastSyncedAt > synced, "last checked advances")
  Equal(market(db).latest[12363].day, 100, "item observed does not advance")
  Equal(market(db).latest[12363].price, 900)
  Equal(market(db).daily[12363][adapter.Today()], nil)
end)

Test("session crossing day boundary warns and preserves Auctionator raw-day attribution", function()
  local adapter, _, db = Mock.Adapter()
  Mock.epoch = Auctionator.Constants.SCAN_DAY_0 + 100 * 86400 + 86398
  Mock.SetItem(12363, 100, 900, 950)
  adapter.Start(function() end) Mock.Advance(1)
  Equal(A.runtime.state, "ready")
  Mock.Advance(2) Mock.SetItem(12363, 100, 800, 950, 5, 800)
  Mock.Notify() Mock.Advance(1)
  Equal(adapter.Today(), 101) Equal(A.runtime.state, "warning") Contains(A.runtime.message, "/reload")
  Equal(market(db).latest[12363].day, 100) Equal(market(db).latest[12363].price, 800)
  Equal(market(db).daily[12363][101], nil)
end)
