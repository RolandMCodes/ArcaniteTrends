local function row(id, day, low, high, quantity)
  return { itemId = id, day = day, low = low, high = high, maxAvailable = quantity }
end
local function market(db) return db.markets["Mankrik Alliance"] end

Test("new database has only the target market and tracked items", function()
  local _, db = Mock.Core()
  Equal(db.schemaVersion, 1)
  Truth(market(db).daily[12363]) Truth(market(db).daily[12359]) Truth(market(db).daily[12360])
  Equal(market(db).daily[999], nil)
  Equal(db.markets["Mankrik Horde"], nil)
end)

Test("daily merges retain extrema, availability, old days and independent copies", function()
  local core, db = Mock.Core()
  local original = row(12363, 100, 900, 1100, 2)
  Equal(core.MergeRows(db, { original }), 1)
  original.low = 1
  Equal(market(db).daily[12363][100].low, 900)
  Equal(core.MergeRows(db, { row(12363, 100, 950, 1050, 1) }), 0)
  Equal(core.MergeRows(db, { row(12363, 100, 850, 1200, 8), row(12363, 140, 1500, 1500) }), 2)
  local old = market(db).daily[12363][100]
  Equal(old.low, 850) Equal(old.high, 1200) Equal(old.maxAvailable, 8)
  Truth(market(db).daily[12363][100], "40-day history must survive newer observations")
end)

Test("validation rejects invalid values and treats zero prices as missing", function()
  local core = Mock.Core()
  for _, candidate in ipairs({
    row(999, 100, 1, 1), row(12363, -1, 1, 1), row(12363, 1.5, 1, 1),
    row(12363, 100, -1, 1), row(12363, 100, 1.5, 2), row(12363, 100, 3, 2),
    row(12363, 100, math.huge, math.huge), row(12363, 100, 0/0, 3),
    row(12363, 100, "10", 10), row(12363, 100, 1, 2, -1),
    row(12363, 100, 1, 2, 1.5), row(12363, 100, nil, nil),
  }) do Equal(core.ValidateRow(candidate), nil) end
  local partial = core.ValidateRow(row(12363, 100, 0, 200))
  Truth(partial) Equal(partial.low, nil) Equal(partial.high, 200)
  local quantityOnly = core.ValidateRow(row(12363, 100, nil, nil, 0))
  Truth(quantityOnly) Equal(quantityOnly.maxAvailable, 0)
end)

Test("last seen day never regresses and missing prices never overwrite it", function()
  local core, db = Mock.Core()
  Truth(core.MergeLatest(db, 12363, 100, 100))
  Equal(core.MergeLatest(db, 12363, 200, 99), false)
  Equal(core.MergeLatest(db, 12363, 0, 101), false)
  Equal(core.MergeLatest(db, 12363, 100, 100), false)
  Truth(core.MergeLatest(db, 12363, 110, 100))
  Equal(market(db).latest[12363].price, 110)
  Equal(market(db).latest[12363].day, 100)
end)

Test("seed import is atomic, idempotent, validates market and keeps price gaps", function()
  local core, db = Mock.Core()
  local seed = { version = 1, market = core.MARKET, id = "synthetic-one", rows = {
    row(12363, 100, 900, 950), row(12363, 102, 1000, 1100), row(12360, 101, 1200, 1250),
  } }
  Equal(core.MergeSeed(db, seed), 3)
  Equal(core.MergeSeed(db, seed), 0)
  Equal(market(db).daily[12363][101], nil)
  Equal(market(db).latest[12363], nil, "daily seeds do not manufacture last-seen prices")
  seed.rows[1].low = 1
  Equal(market(db).daily[12363][100].low, 900)
  Equal(core.MergeSeed(db, { version = 1, market = core.MARKET, id = "bad", rows = {
    row(12363, 105, 100, 200), row(999, 106, 1, 1),
  } }), 0)
  Equal(market(db).daily[12363][105], nil)
  Equal(db.seedImports.bad, nil)
  Equal(core.MergeSeed(db, { version = 1, market = "Mankrik Horde", id = "wrong", rows = {} }), 0)
end)

Test("saved-variable round trip sanitizes records without losing old history", function()
  local core, db = Mock.Core()
  core.MergeRows(db, { row(12363, 100, 900, 950, 4), row(12360, 200, 1200, 1300) })
  core.MergeLatest(db, 12363, 940, 100)
  db.lastSyncedAt = 1700000000
  db.ui = { width = 940, height = 820 }
  db.seedImports.synthetic = true
  -- WoW's SavedVariables serializes tables and numbers. This copied table models
  -- a new Lua session with no references into the previous runtime.
  local saved = Mock.Copy(db)
  saved.markets["Mankrik Horde"] = { private = "must not import" }
  saved.markets["Mankrik Alliance"].daily[999] = { [100] = { low = 1, high = 1 } }
  saved.markets["Mankrik Alliance"].daily[12363][101] = { low = -1, high = 9 }
  local restored = core.InitDB(saved)
  Equal(market(restored).daily[12363][100].maxAvailable, 4)
  Equal(market(restored).daily[12363][101], nil)
  Equal(market(restored).daily[999], nil)
  Equal(restored.markets["Mankrik Horde"], nil)
  Equal(market(restored).latest[12363].price, 940)
  Equal(restored.ui.width, 940)
  Equal(restored.lastSyncedAt, 1700000000)
  Truth(restored.seedImports.synthetic)
  saved.markets["Mankrik Alliance"].daily[12363][100].low = 1
  Equal(market(restored).daily[12363][100].low, 900)
  local future = { schemaVersion = 99, sentinel = "preserved" }
  local invalid, message = core.InitDB(future)
  Equal(invalid, nil) Contains(message, "unsupported") Equal(future.sentinel, "preserved")
end)

Test("nominal day conversion is calendar-based across leap, year and DST dates", function()
  local core = Mock.Core()
  local cases = {
    {0, "2020-01-01"}, {59, "2020-02-29"}, {67, "2020-03-08"}, {305, "2020-11-01"},
    {365, "2020-12-31"}, {366, "2021-01-01"}, {1530, "2024-03-10"}, {1768, "2024-11-03"},
    {2441, "2026-09-07"},
  }
  for _, entry in ipairs(cases) do Equal(core.DateString(entry[1]), entry[2]) end
  Equal(core.DayLabel(59), "2/29")
  Equal(core.DateString(nil), "Unknown date")
  Equal(core.DateString(-1), "Unknown date")
end)

Test("median, formatting and auction cut preserve copper rounding", function()
  local core = Mock.Core()
  Equal(core.Median({}), nil) Equal(core.Median({5, 1, 3}), 3)
  local values = {5, 1, 2, 4}
  Equal(core.Median(values), 3) Equal(values[1], 5)
  Equal(core.Median({2, 3}), 3)
  Equal(core.Median({9007199254740989, 9007199254740990}), 9007199254740990)
  Equal(core.Net(19), 19) Equal(core.Net(20), 19) Equal(core.Net(1112200), 1056590)
  Equal(core.FormatCopper(919994), "91g 99s 94c")
  Equal(core.FormatCopper(134171, true), "+13g 41s 71c")
  Equal(core.FormatCopper(-2425), "-0g 24s 25c")
  Equal(core.FormatCopper(2425.5), "0g 24s 26c")
  Equal(core.FormatCopper(nil), "Unavailable")
end)

Test("30 calendar dates preserve gaps and use hidden seven-day warm-up", function()
  local core, db = Mock.Core()
  core.MergeRows(db, {
    row(12363, 65, 10, 50), row(12363, 66, 20, 60), row(12363, 71, 30, 70),
    row(12360, 65, 1, 100), row(12360, 66, 2, 200), row(12360, 71, 3, 300),
    row(12363, 100, 900, 950), row(12363, 101, 9999, 9999),
  })
  local view = core.BuildView(db, 100)
  Equal(view.startDay, 71) Equal(#view.charts, 3)
  local crystal, arcanite = view.charts[1], view.charts[3]
  Equal(#crystal.days, 30) Equal(crystal.coverage, 2)
  Equal(crystal.days[1].day, 71) Equal(crystal.days[1].median7, 20)
  Equal(arcanite.days[1].median7, 200, "selling uses daily highs")
  Equal(crystal.days[2].day, 72) Equal(crystal.days[2].low, nil)
  Equal(crystal.days[2].median7, nil, "out-of-window observation must not count")
  Equal(crystal.days[30].day, 100) Equal(crystal.days[30].median7, nil)
  Equal(crystal.days[30].high, 950, "future data cannot leak into the view")
end)

Test("quote requires three last-seen prices from exactly one recorded day", function()
  local core, db = Mock.Core()
  core.MergeLatest(db, 12363, 919994, 100)
  core.MergeLatest(db, 12359, 2425, 100)
  Equal(core.BuildView(db, 100).quote, nil)
  core.MergeLatest(db, 12360, 1112200, 100)
  local quote = core.BuildView(db, 100).quote
  Equal(quote.cost, 922419) Equal(quote.net, 1056590) Equal(quote.profit, 134171)
  core.MergeLatest(db, 12363, 800000, 101)
  Equal(core.BuildView(db, 101).quote, nil)
  Equal(core.BuildView(db, 99).quote, nil)
end)

Test("spread uses independent conservative and optimistic extrema and latest complete date", function()
  local core, db = Mock.Core()
  core.MergeRows(db, {
    row(12363, 99, 919994, 930000), row(12359, 99, 2425, 3000),
    row(12360, 99, 1112200, 1200000), row(12360, 100, 2000000, 2100000),
  })
  local spread = core.BuildView(db, 100).spread
  Equal(spread.day, 99) Equal(spread.conservative, 123590) Equal(spread.optimistic, 217581)
  Equal(core.BuildView(db, 129).spread, nil, "outside display range is unavailable")
  core.MergeRows(db, { row(12363, 100, 100, 200), row(12359, 100, 0, 300) })
  Equal(core.BuildView(db, 100).spread.day, 99, "partial low/high input remains unavailable")
end)
