import { DatabaseSync } from 'node:sqlite';
import { createHash } from 'node:crypto';
import { mkdir, readFile, readdir, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const addonRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const targetItems = new Set([12359, 12360, 12363]);
const epoch = Date.UTC(2020, 0, 1);

export function seedRows(records) {
  return records.map((row) => {
    if (!targetItems.has(row.item_id)) throw new Error('Unexpected item in seed query.');
    if (!/^\d{4}-\d{2}-\d{2}$/.test(row.local_date)) throw new Error('Invalid recorded date.');
    const stamp = Date.parse(`${row.local_date}T00:00:00Z`);
    if (!Number.isFinite(stamp) || new Date(stamp).toISOString().slice(0, 10) !== row.local_date) throw new Error('Invalid recorded date.');
    const day = (stamp - epoch) / 86400000;
    if (!Number.isSafeInteger(day) || day < 0 || day > 36525) throw new Error('Recorded date outside supported range.');
    const low = row.low_min_buyout;
    const high = row.high_min_buyout;
    if (![low, high].every((v) => Number.isSafeInteger(v) && v > 0) || low > high) throw new Error('Invalid recorded price range.');
    const available = row.max_available;
    if (available != null && (!Number.isSafeInteger(available) || available < 0)) throw new Error('Invalid recorded quantity.');
    return { itemId: row.item_id, day, low, high, ...(available == null ? {} : { maxAvailable: available }) };
  }).sort((a, b) => a.day - b.day || a.itemId - b.itemId);
}

export function serializeSeed(rows) {
  const id = createHash('sha256').update(JSON.stringify(rows)).digest('hex');
  const luaRows = rows.map((r) => `    {itemId=${r.itemId},day=${r.day},low=${r.low},high=${r.high}${r.maxAvailable == null ? '' : `,maxAvailable=${r.maxAvailable}`}},`).join('\n');
  return `-- PRIVATE local price history: never include this generated file in a public release.\nlocal _, A = ...\nA.Seed = {version=1,id="${id}",market="Mankrik Alliance",rows={\n${luaRows}\n}}\n`;
}

async function findDatabases(directory) {
  const results = [];
  for (const entry of await readdir(directory, { withFileTypes: true }).catch(() => [])) {
    const path = resolve(directory, entry.name);
    if (entry.isDirectory()) results.push(...await findDatabases(path));
    else if (entry.isFile() && entry.name.endsWith('.sqlite') && entry.name !== 'metadata.sqlite') {
      let db;
      try {
        db = new DatabaseSync(path, { readOnly: true });
        if (db.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name='auctionator_daily_prices'").get()) results.push(path);
      } finally { db?.close(); }
    }
  }
  return results;
}

export async function exportSeed(databasePath, outputPath) {
  if (resolve(outputPath).toLowerCase() === resolve(addonRoot, 'ArcaniteTrends', 'SeedData.lua').toLowerCase()) throw new Error('Refusing to overwrite the public empty seed. Choose a private output folder.');
  const db = new DatabaseSync(databasePath, { readOnly: true });
  let rows;
  try {
    rows = seedRows(db.prepare('SELECT local_date,item_id,low_min_buyout,high_min_buyout,max_available FROM auctionator_daily_prices WHERE item_id IN (12359,12360,12363) ORDER BY local_date,item_id').all());
  } finally { db.close(); }
  const body = serializeSeed(rows);
  await mkdir(dirname(outputPath), { recursive: true });
  // Do not rewrite an identical personal seed on repeated export.
  if (await readFile(outputPath, 'utf8').catch(() => null) !== body) await writeFile(outputPath, body, 'utf8');
  return rows.length;
}

async function main() {
  const args = process.argv.slice(2);
  let databasePath;
  let outputPath = resolve(addonRoot, 'private', 'SeedData.lua');
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--database' && args[i + 1]) databasePath = resolve(args[++i]);
    else if (args[i] === '--output' && args[i + 1]) outputPath = resolve(args[++i]);
    else throw new Error('Usage: npm run seed -- [--database path.sqlite] [--output private/SeedData.lua]');
  }
  if (!databasePath) {
    const matches = await findDatabases(resolve(addonRoot, '..', '.wrangler', 'state', 'v3', 'd1'));
    if (matches.length !== 1) throw new Error('Specify --database: expected exactly one local tracker history database.');
    [databasePath] = matches;
  }
  const count = await exportSeed(databasePath, outputPath);
  console.log(`Prepared ${count} private Auctionator daily records. No TSM records or account data exported.`);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main().catch((error) => { console.error(error.message); process.exitCode = 1; });
