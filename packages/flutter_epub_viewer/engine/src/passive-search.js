export function searchPublicationText(section, query) {
  const document = section.document;
  const body = document.body || document.getElementsByTagName('body')[0];
  const needle = query.toLowerCase().replace(/\s+/gu, ' ').trim();
  if (!body || !needle) return [];
  const walker = document.createTreeWalker(body, 4);
  let text = '';
  const positions = [];
  let previousBlock;
  let node;
  const blocks = new Set(['P', 'DIV', 'LI', 'H1', 'H2', 'H3', 'H4', 'H5', 'H6', 'BLOCKQUOTE', 'TD', 'TH', 'PRE', 'SECTION', 'ARTICLE']);
  while ((node = walker.nextNode())) {
    let parent = node.parentElement;
    let hidden = false;
    let block;
    while (parent && parent !== body) {
      if (parent.hasAttribute('hidden') || parent.getAttribute('aria-hidden') === 'true' ||
          /(?:display\s*:\s*none|visibility\s*:\s*hidden)/i.test(parent.getAttribute('style') || '') ||
          ['SCRIPT', 'STYLE', 'TEMPLATE'].includes(parent.tagName.toUpperCase())) hidden = true;
      if (!block && blocks.has(parent.tagName.toUpperCase())) block = parent;
      parent = parent.parentElement;
    }
    if (hidden) continue;
    if (previousBlock && block !== previousBlock && text && !text.endsWith(' ')) {
      text += ' ';
      positions.push({ node, start: 0, end: 0 });
    }
    previousBlock = block;
    let offset = 0;
    for (const character of node.textContent) {
      const end = offset + character.length;
      const folded = /\s/u.test(character) ? ' ' : character.toLowerCase();
      if (folded === ' ' && text.endsWith(' ')) {
        positions[positions.length - 1].endNode = node;
        positions[positions.length - 1].end = end;
      } else {
        text += folded;
        for (let index = 0; index < folded.length; index++) positions.push({ node, start: offset, end });
      }
      offset = end;
    }
  }
  const matches = [];
  for (let start = text.indexOf(needle); start !== -1; start = text.indexOf(needle, start + 1)) {
    if (matches.length === 500) { matches.incomplete = true; break; }
    const first = positions[start];
    const last = positions[start + needle.length - 1];
    const range = document.createRange();
    range.setStart(first.node, first.start);
    range.setEnd(last.endNode || last.node, last.end);
    matches.push({ cfi: section.cfiFromRange(range), excerpt: range.toString().slice(0, 160) });
  }
  return matches;
}
