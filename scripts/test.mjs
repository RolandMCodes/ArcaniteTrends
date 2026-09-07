import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');
const luaparse = require('luaparse');
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const addonRoot = path.join(root, 'ArcaniteTrends');
const sources = fs.readdirSync(addonRoot).filter(name => name.endsWith('.lua')).sort();
const toc = fs.readFileSync(path.join(addonRoot, 'ArcaniteTrends.toc'), 'utf8');
assert(/^## Dependencies: Auctionator\s*$/m.test(toc), 'Auctionator must be a required dependency');
assert(/^## SavedVariables: ArcaniteTrendsDB\s*$/m.test(toc), 'only addon-owned SavedVariables may be declared');
const tocSources = toc.split(/\r?\n/).map(line => line.trim()).filter(line => line.endsWith('.lua'));
assert.deepEqual([...tocSources].sort(), sources, 'TOC source list must match the audited addon files');
assert(tocSources.indexOf('AuctionatorAdapter.lua') < tocSources.indexOf('Main.lua'), 'adapter must load before Main');
assert(tocSources.indexOf('UI.lua') < tocSources.indexOf('Main.lua'), 'UI must load before Main');
const forbidden = new Set([
  'QueryAuctionItems', 'CanSendAuctionQuery', 'PlaceAuctionBid', 'StartAuction',
  'CancelAuction', 'SendAuctionQuery', 'SearchForItemKeys', 'SendSearchQuery',
  'SendSellSearchQuery', 'PostItem', 'PostCommodity', 'ConfirmCommoditiesPurchase',
  'StartCommoditiesPurchase', 'BuyCommodity', 'DoTradeSkill', 'CastSpellByName',
  'RunMacro', 'RunMacroText', 'UseAction', 'UseInventoryItem', 'UseContainerItem',
  'SendChatMessage', 'SendAddonMessage', 'SendWho', 'loadstring', 'dofile',
  'loadfile', 'require', 'setfenv', 'getfenv', 'DownloadFile', 'HttpRequest',
  'PerformHttpRequest', 'ReadFile', 'WriteFile', 'CreateFile', 'ShellExecute',
]);
function audit(node, file) {
  if (!node || typeof node !== 'object') return;
  if (node.type === 'Identifier') {
    assert(!forbidden.has(node.name), `${file}: forbidden capability ${node.name}`);
    assert(!['io', 'os', 'socket', 'http'].includes(node.name), `${file}: external runtime ${node.name}`);
  }
  for (const value of Object.values(node)) {
    if (Array.isArray(value)) value.forEach(child => audit(child, file));
    else if (value && typeof value === 'object') audit(value, file);
  }
}
const sourceMap = new Map();
for (const name of sources) {
  const code = fs.readFileSync(path.join(addonRoot, name), 'utf8');
  audit(luaparse.parse(code, { luaVersion: '5.1' }), name);
  assert(!/[A-Z]:[\\/](?:Users|Program Files)/i.test(code), `${name}: machine-specific path`);
  assert(!/\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})\b/.test(code), `${name}: credential pattern`);
  sourceMap.set(name, code);
}
console.log(`PASS Lua 5.1 syntax and read-only capability audit (${sources.length} source files)`);
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
lua.lua_newtable(L);
for (const [name, code] of sourceMap) {
  lua.lua_pushstring(L, to_luastring(code));
  lua.lua_setfield(L, -2, to_luastring(name));
}
lua.lua_setglobal(L, to_luastring('__addonSources'));
function execute(code, name) {
  const bytes = to_luastring(code);
  let result = lauxlib.luaL_loadbuffer(L, bytes, bytes.length, to_luastring(name));
  if (result === lua.LUA_OK) result = lua.lua_pcall(L, 0, 0, 0);
  if (result !== lua.LUA_OK) throw new Error(`${name}: ${to_jsstring(lua.lua_tostring(L, -1))}`);
}
try {
  execute(fs.readFileSync(path.join(root, 'tests', 'mock.lua'), 'utf8'), 'mock.lua');
  for (const name of fs.readdirSync(path.join(root, 'tests')).filter(name => name.endsWith('.test.lua')).sort()) {
    execute(fs.readFileSync(path.join(root, 'tests', name), 'utf8'), name);
  }
  execute('FinishTests()', 'test-results');
} finally {
  lua.lua_close(L);
}
