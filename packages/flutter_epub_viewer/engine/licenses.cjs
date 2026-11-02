const fs = require('node:fs');
const path = require('node:path');
const lock = JSON.parse(fs.readFileSync('package-lock.json', 'utf8'));
const sections = [fs.readFileSync('../LICENSE', 'utf8'), fs.readFileSync('LICENSE', 'utf8')];
for (const [directory, entry] of Object.entries(lock.packages).sort(([left], [right]) => left.localeCompare(right, 'en'))) {
  if (!directory || entry.dev) continue;
  const metadata = JSON.parse(fs.readFileSync(path.join(directory, 'package.json'), 'utf8'));
  const files = fs.readdirSync(directory).filter(name => /^licen[cs]e(?:\.|$)/i.test(name)).sort();
  const readme = fs.readdirSync(directory).find(name => /^readme(?:\.|$)/i.test(name));
  const embedded = !files.length && readme ? fs.readFileSync(path.join(directory, readme), 'utf8').match(/^##? Licen[cs]e\s*\n[\s\S]+/im) : null;
  if (!files.length && !embedded) throw Error('License text is missing for ' + metadata.name);
  sections.push(`${metadata.name} ${metadata.version}\n${entry.resolved}\n${entry.integrity}\n` +
    (files.length ? files.map(file => fs.readFileSync(path.join(directory, file), 'utf8')).join('\n') : embedded[0]));
}
fs.writeFileSync('../assets/THIRD-PARTY-LICENSES.txt', sections.join('\n\n----------------------------------------\n\n'));
