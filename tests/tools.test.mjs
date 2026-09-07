import test from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { mkdtemp, readFile, rm, mkdir, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { resolve, join } from 'node:path';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { seedRows, serializeSeed, exportSeed } from '../scripts/export-seed.mjs';
import { publicFiles } from '../scripts/prepare-release.mjs';

test('seed is deterministic numeric Lua with correct leap/DST-independent days', () => {
  const rows = seedRows([
    { item_id:12363, local_date:'2024-03-10', low_min_buyout:100, high_min_buyout:200, max_available:null },
    { item_id:12360, local_date:'2024-02-29', low_min_buyout:300, high_min_buyout:400, max_available:0 },
  ]);
  assert.equal(rows[0].day, 1520);
  assert.equal(rows[1].day, 1530);
  assert.equal(rows[0].maxAvailable, 0);
  assert.equal(rows[1].maxAvailable, undefined);
  assert.equal(serializeSeed(rows), serializeSeed(rows));
  assert.ok(!serializeSeed(rows).includes('source_modified_at'));
  assert.throws(() => seedRows([{ item_id:12363, local_date:'2024-02-30', low_min_buyout:1, high_min_buyout:2 }]));
  assert.throws(() => seedRows([{ item_id:999, local_date:'2024-02-29', low_min_buyout:1, high_min_buyout:2 }]));
  assert.throws(() => seedRows([{ item_id:12363, local_date:'2024-02-29', low_min_buyout:3, high_min_buyout:2 }]));
});

test('export queries only tracked Auctionator records and leaves SQLite untouched', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'arcanite-seed-test-'));
  try {
    const path = join(dir, 'history.sqlite');
    const db = new DatabaseSync(path);
    db.exec('CREATE TABLE auctionator_daily_prices (item_id INTEGER,local_date TEXT,low_min_buyout INTEGER,high_min_buyout INTEGER,max_available INTEGER); CREATE TABLE item_prices (secret TEXT);');
    db.prepare('INSERT INTO auctionator_daily_prices VALUES (?,?,?,?,?)').run(12363,'2026-09-01',919994,950000,12);
    db.prepare('INSERT INTO auctionator_daily_prices VALUES (?,?,?,?,?)').run(777,'2026-09-01',10,20,3);
    db.prepare('INSERT INTO item_prices VALUES (?)').run('private unrelated record');
    db.close();
    const before = createHash('sha256').update(await readFile(path)).digest('hex');
    const output = join(dir,'private','SeedData.lua');
    assert.equal(await exportSeed(path,output),1);
    const body = await readFile(output,'utf8');
    assert.match(body,/itemId=12363/);
    assert.ok(!body.includes('itemId=777') && !body.includes('private unrelated record') && !body.includes(path));
    assert.equal(await exportSeed(path,output),1);
    assert.equal(createHash('sha256').update(await readFile(path)).digest('hex'),before);
    await assert.rejects(exportSeed(path,resolve('ArcaniteTrends','SeedData.lua')),/public empty seed/);
  } finally { await rm(dir,{recursive:true,force:true}); }
});

test('public release allowlist excludes private history, dependencies and desktop project', async () => {
  const paths = await publicFiles();
  assert.ok(paths.includes('ArcaniteTrends/SeedData.lua'));
  assert.ok(paths.includes('scripts/export-seed.mjs'));
  assert.ok(paths.every((p) => !/^(private|dist|node_modules|app|db|lib)\//.test(p)));
  assert.ok(paths.every((p) => !/\.(sqlite|db)$/.test(p)));
});

test('Windows installer previews, installs and backs up only the named addon', {skip:process.platform !== 'win32'}, async () => {
  const dir = await mkdtemp(join(tmpdir(),'arcanite-installer-test-'));
  try {
    const wowRoot = join(dir,'_classic_era_');
    const addons = join(wowRoot,'Interface','AddOns');
    await mkdir(join(addons,'Auctionator'),{recursive:true});
    await writeFile(join(addons,'Auctionator','Auctionator.toc'),'synthetic fixture');
    const run = (extra=[]) => spawnSync('powershell.exe',['-NoProfile','-ExecutionPolicy','Bypass','-File',resolve('scripts/install.ps1'),'-WowRoot',wowRoot,'-BackupRoot',join(dir,'backups'),...extra],{encoding:'utf8'});
    let result=run(['-WhatIf']);
    assert.equal(result.status,0,result.stderr);
    await assert.rejects(readFile(join(addons,'ArcaniteTrends','Main.lua')));
    result=run();
    assert.equal(result.status,0,result.stderr);
    assert.equal(await readFile(join(addons,'ArcaniteTrends','Main.lua'),'utf8'),await readFile('ArcaniteTrends/Main.lua','utf8'));
    result=run();
    assert.equal(result.status,0,result.stderr);
    assert.match(result.stdout,/backed up/);
    assert.equal(await readFile(join(addons,'Auctionator','Auctionator.toc'),'utf8'),'synthetic fixture');
  } finally { await rm(dir,{recursive:true,force:true}); }
});
