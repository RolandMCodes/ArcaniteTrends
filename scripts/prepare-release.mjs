import { mkdir, readFile, readdir, copyFile, writeFile, lstat } from 'node:fs/promises';
import { resolve, dirname, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
export const runtimeFiles = ['ArcaniteTrends.toc', 'Core.lua', 'SeedData.lua', 'AuctionatorAdapter.lua', 'UI.lua', 'Main.lua'];

export async function publicFiles() {
  const paths = [
    ...runtimeFiles.map((name) => `ArcaniteTrends/${name}`),
    'README.md', 'LICENSE', '.gitignore', 'package.json', 'package-lock.json',
    'scripts/export-seed.mjs', 'scripts/install.ps1', 'scripts/prepare-release.mjs', 'scripts/test.mjs',
  ];
  for (const entry of await readdir(resolve(root, 'tests'), { withFileTypes: true })) {
    if (entry.isFile() && /\.(lua|mjs)$/.test(entry.name)) paths.push(`tests/${entry.name}`);
  }
  for (const path of paths) {
    if ((await lstat(resolve(root, path))).isSymbolicLink()) throw new Error(`Symlink forbidden in public release: ${path}`);
    const content = await readFile(resolve(root, path), 'utf8');
    // Paths, generated personal histories, tokens, and SavedVariables are never shipped.
    if (/C:[\\/]Users[\\/]|github_pat_[A-Za-z0-9_]+|gh[pousr]_[A-Za-z0-9]+/.test(content)) throw new Error(`Private material detected in ${path}`);
    if (path.startsWith('ArcaniteTrends/') && content.includes('PRIVATE local price history')) throw new Error(`Personal seed detected in ${path}`);
  }
  const seed = await readFile(resolve(root, 'ArcaniteTrends/SeedData.lua'), 'utf8');
  if (!/rows\s*=\s*\{\s*\}/.test(seed) || /itemId\s*=\s*\d/.test(seed)) throw new Error('Public seed must be empty.');
  return paths.sort();
}

export async function prepareRelease(outputPath) {
  const paths = await publicFiles();
  const distRoot = resolve(root, 'dist');
  outputPath = resolve(outputPath);
  if (!outputPath.startsWith(distRoot + '/') && !outputPath.startsWith(distRoot + '\\')) throw new Error('Release output must be a child of addon/dist.');
  if (relative(distRoot, outputPath).startsWith('..')) throw new Error('Invalid release path.');
  // A fresh destination prevents accidentally republishing files from an older build.
  await mkdir(outputPath, { recursive: false });
  const manifest = [];
  for (const path of paths) {
    const destination = resolve(outputPath, path);
    await mkdir(dirname(destination), { recursive: true });
    await copyFile(resolve(root, path), destination);
    const hash = createHash('sha256').update(await readFile(destination)).digest('hex');
    manifest.push({ path, sha256: hash });
  }
  await writeFile(resolve(outputPath, 'release-manifest.json'), JSON.stringify(manifest, null, 2) + '\n');
  return manifest;
}

async function main() {
  await mkdir(resolve(root, 'dist'), { recursive: true });
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const outputPath = resolve(root, 'dist', `source-${stamp}`);
  const manifest = await prepareRelease(outputPath);
  console.log(JSON.stringify({ outputPath, files: manifest.length, personalData: false }));
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main().catch((error) => { console.error(error.message); process.exitCode = 1; });
