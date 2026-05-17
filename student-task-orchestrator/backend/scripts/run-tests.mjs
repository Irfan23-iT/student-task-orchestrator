import { readdirSync } from 'node:fs';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const testDir = new URL('../lib/', import.meta.url);
const testDirPath = fileURLToPath(testDir);
const testFiles = readdirSync(testDir)
  .filter((file) => file.endsWith('.test.js'))
  .sort();

if (!testFiles.length) {
  console.log('No backend tests found.');
  process.exit(0);
}

for (const file of testFiles) {
  const result = spawnSync(process.execPath, [join(testDirPath, file)], {
    stdio: 'inherit'
  });

  if (result.status !== 0) {
    process.exit(result.status ?? 1);
  }
}
