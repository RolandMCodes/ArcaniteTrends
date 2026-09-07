# ArcaniteTrends

A free display addon for **World of Warcraft Classic Era**, showing the Mankrik Alliance Arcanite transmute market from **Auctionator** observations. Open it with the minimap button or **`/arc`**. There is no keybind and the window never opens automatically.

The addon runs entirely in WoW. It needs Auctionator enabled; it does not need TSM, a browser, Node.js, or a desktop service during play.

## What you see

- Three aligned 30-day charts for Arcane Crystal (12363), Thorium Bar (12359), and Arcanite Bar (12360), each with its own price scale.
- Daily low/high whiskers and a seven-day median of reagent daily lows or Arcanite daily highs. Medians require at least three observed dates in the seven-day window.
- Last-seen minimum buyouts with their recorded day, observed-day coverage, and tooltips with prices and maximum observed availability.
- An indicative transmute margin when the three last-seen prices share a recorded day; conservative and optimistic scenarios from the latest complete daily range.

These ranges describe the lowest and highest **minimum buyout observed across scans that day**. They are not the range of every listing and do not establish completed purchases or sales. Maximum availability depends on which results Auctionator processed. Missing days remain gaps. Three same-day prices may still have been observed at different times.

The 5% auction cut is rounded down in copper. A 30-silver 24-hour deposit is shown as money held and is not subtracted, because it is returned after a successful sale.

## Installation

1. Close World of Warcraft.
2. Copy the `ArcaniteTrends` folder into your `_classic_era_/Interface/AddOns` directory alongside Auctionator. The folder must contain `ArcaniteTrends.toc` directly.
3. Start Classic Era and enable both Auctionator and ArcaniteTrends in the addon list.
4. Log in and click the gold-bar minimap icon or type `/arc`. Drag the window header to move it and its lower-right corner to resize it. Drag the minimap icon to reposition it. Escape closes the window.

On Windows, the included installer can do step 2 and back up an existing addon version:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1
```

For a nonstandard installation, supply `-WowRoot 'D:\Games\World of Warcraft\_classic_era_'`. Use `-WhatIf` to preview the target. The script refuses to run while WoW is open and touches only this addon's installation folder. It never changes Auctionator or WoW's SavedVariables files. Backups are kept under `private/backups`; restore the backed-up addon folder while WoW is closed if needed. Future updates preserve your history in WoW's normal SavedVariables.

## Scans and retained history

Continue your normal Auctionator scanning. The companion reads the three items after Auctionator finishes processing and redraws an open window immediately. Opening the window also checks for updates. It does not issue scans itself.

The addon retains its own copy of these three items in account-level `ArcaniteTrendsDB`, so Auctionator's default 21-day history pruning does not erase the companion's archive. WoW writes this data to disk on `/reload`, logout, or exit. A crash before saving can lose changes from the current session.

Collection is specific to Mankrik Alliance. Other characters can view saved Mankrik history, with collection marked paused. Auctionator's history interface is internal; an incompatible update shows an error and leaves retained charts available.

Auctionator records day buckets, not exact observation timestamps. A search for an unrelated item cannot make these three items current. The companion's last-check time is shown separately. Auctionator v335 can continue using the previous day bucket in a session crossing its day boundary; the companion warns and suggests a manual `/reload` instead of inventing a new observation date.

## Optional private history seed

If you have an existing local Arcanite Ledger database, the included exporter reads its Auctionator rows using a read-only SQLite connection. It exports only the three tracked items, without TSM records, account names, or file paths. This is a one-time convenience; the desktop tracker is not needed afterward.

With Node.js 22.13 or newer:

```powershell
node .\scripts\export-seed.mjs --database 'D:\Tracker\history.sqlite'
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1
```

The exporter generates `private/SeedData.lua`, which the installer automatically uses when present. A custom seed can be supplied with `-SeedFile`. Duplicate seed imports are harmless. Never publish your generated seed, `private` folder, or SavedVariables. The public `ArcaniteTrends/SeedData.lua` is intentionally empty.

## Development and verification

```text
npm ci --ignore-scripts
npm test
npm run test:tools
npm run release
```

Development dependencies are pinned and never installed into WoW. Lua files are checked against Lua 5.1 syntax, then run using Fengari with mocked WoW/Auctionator interfaces. Tests cover history retention, dates, calculations, asynchronous processing and the UI lifecycle. The release command builds a new allowlisted source directory under `dist`, audits the empty seed and private-data patterns, and records SHA-256 hashes.

In-game validation remains necessary: test `/arc`, the minimap button, window size/position, date tooltips, a normal Auctionator search and full scan, and preservation after `/reload` and relogging. Automated mocks cannot prove client rendering or live addon coexistence. Version 0.1.0 is an initial release until those checks have been performed in the actual Classic Era client.

## Addon policy and source

Source is freely available under the MIT license at <https://github.com/RolandMCodes/ArcaniteTrends>. ArcaniteTrends is designed to follow [Blizzard's UI Add-On Development Policy](https://us.forums.blizzard.com/en/wow/t/ui-add-on-development-policy/24534/1). Blizzard's policy requires free distribution and visible source even though the general MIT license permits broad reuse.

The addon contains no paid features, ads, donation prompts, extra auction queries, gameplay automation, simulated inputs, external connections, or runtime file access. It reads existing addon data and uses ordinary WoW UI and SavedVariables facilities. It processes only three items with reusable chart objects and event-driven updates. It respects Blizzard's API restrictions; compatibility failures are reported, not bypassed. Auctionator remains a separate dependency and is not redistributed here.
