const fs = require('node:fs');
const path = require('node:path');
const { createHash } = require('node:crypto');
const root = path.resolve(__dirname, '..');
for (const line of fs.readFileSync(path.join(root, 'ASSETS.sha256'), 'utf8').trim().split('\n')) {
  const [expected, relative] = line.split('  ');
  if (!/^assets\/[A-Za-z0-9.-]+$/.test(relative)) throw Error('Invalid asset manifest path');
  const actual = createHash('sha256').update(fs.readFileSync(path.join(root, relative))).digest('hex');
  if (actual !== expected) throw Error('Runtime asset does not match the manifest: ' + relative);
  console.log('Verified ' + relative + ': ' + actual);
}
