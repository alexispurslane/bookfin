const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { JSDOM } = require('jsdom');

async function open(chapter) {
  const dom = new JSDOM('<html><body></body></html>', { url: 'https://bookfin-runtime.invalid/', runScripts: 'outside-only', pretendToBeVisual: true });
  dom.window.eval(fs.readFileSync(path.join(__dirname, '../../assets/epub.js'), 'utf8'));
  const files = {
    'META-INF/container.xml': '<container><rootfiles><rootfile full-path="OPS/book.opf"/></rootfiles></container>',
    'OPS/book.opf': '<package version="3.0"><metadata/><manifest><item id="one" href="one.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="one"/></spine></package>',
    'OPS/one.xhtml': chapter,
  };
  const book = dom.window.ePub(undefined, { requestMethod: async url => {
    const key = new URL(url).pathname.slice(1);
    if (!files[key]) throw Error('Missing local document: ' + key);
    return new dom.window.DOMParser().parseFromString(files[key], 'application/xhtml+xml');
  }});
  await book.open('https://bookfin-publication.invalid/', 'directory');
  await book.ready;
  await book.spine.first().load(book.load.bind(book));
  return { dom, book, section: book.spine.first(), close() { book.destroy(); dom.window.close(); } };
}

test('search finds an exact phrase across inline nodes, including more than five nodes', async () => {
  const opened = await open('<html><head><title>Ignored</title></head><body><p>A phrase <em>crosses</em> <b>several</b> <i>inline</i> nodes.</p></body></html>');
  try {
    const hits = opened.section.find('phrase crosses several inline nodes');
    assert.equal(hits.length, 1);
    assert.equal((await opened.book.getRange(hits[0].cfi)).toString(), 'phrase crosses several inline nodes');
  } finally { opened.close(); }
});

test('short documents and repeated occurrences are not omitted', async () => {
  const opened = await open('<html><head/><body><p>Repeat phrase. Repeat phrase.</p></body></html>');
  try {
    assert.equal(opened.section.search('Repeat phrase').length, 2);
  } finally { opened.close(); }
});

test('Unicode lowercase expansion does not silently discard an admitted query', async () => {
  const phrase = 'İ'.repeat(200);
  const opened = await open('<html><head/><body><p>' + phrase + '</p></body></html>');
  try {
    const report = await runtime(opened).searchBook(opened.book, phrase, () => true);
    assert.equal(report.error, null);
    assert.equal(report.hits.length, 1);
    assert.equal(report.hits[0].location.quote, phrase.slice(0, 120));
  } finally { opened.close(); }
});

test('search excludes headings in the head and explicitly hidden text', async () => {
  const opened = await open('<html><head><title>Needle</title></head><body><p hidden="hidden">Needle</p><p style="display:none">Needle</p><h1>Needle</h1></body></html>');
  try {
    assert.equal(opened.section.find('Needle').length, 1);
  } finally { opened.close(); }
});

test('Unicode lowercase expansion cannot shift the returned original range', async () => {
  const opened = await open('<html><head/><body><p>İ 🦦 AFTER</p></body></html>');
  try {
    const hit = opened.section.find('after')[0];
    assert.equal((await opened.book.getRange(hit.cfi)).toString(), 'AFTER');
  } finally { opened.close(); }
});

function runtime(opened) {
  opened.dom.window.eval(fs.readFileSync(path.join(__dirname, '../../assets/reader.js'), 'utf8'));
  return opened.dom.window.bookfinReader;
}

test('an encoded contents fragment resolves to the actual heading, not the chapter start', async () => {
  const opened = await open('<html><head/><body><h1>Beginning</h1><p>Earlier text.</p><h2 id="café">Target note</h2></body></html>');
  try {
    const location = await runtime(opened).resolveDestination(opened.book, 'one.xhtml#caf%C3%A9', 'https://bookfin-publication.invalid/', 'OPS/book.opf');
    assert.equal(location.resource, 'OPS/one.xhtml');
    assert.ok(location.quote.startsWith('Target note'));
    const range = await opened.book.getRange(location.cfi);
    assert.ok(range.startContainer.textContent.includes('Target note'));
    await assert.rejects(() => runtime(opened).resolveDestination(opened.book, 'one.xhtml#missing', 'https://bookfin-publication.invalid/', 'OPS/book.opf'));
  } finally { opened.close(); }
});

test('saved locations collapse to the visible start and reject a mismatched quote', async () => {
  const opened = await open('<html><head/><body><p>🦦 A stable phrase ends here.</p></body></html>');
  try {
    const api = runtime(opened);
    const hit = opened.section.find('stable phrase')[0];
    const location = await api.visibleLocation(opened.book, hit.cfi, 'OPS/one.xhtml');
    const range = await opened.book.getRange(location.cfi);
    assert.equal(range.collapsed, true);
    assert.ok(location.quote.startsWith('stable phrase'));
    await api.verifyLocation(opened.book, location);
    await assert.rejects(() => api.verifyLocation(opened.book, { ...location, quote: 'Wrong book' }));
    await assert.rejects(() => api.verifyLocation(opened.book, { ...location, resource: 'OPS/other.xhtml' }));
  } finally { opened.close(); }
});

test('a failed chapter yields a visible incomplete-search error', async () => {
  const opened = await open('<html><head/><body><p>A searchable phrase.</p></body></html>');
  try {
    opened.section.unload();
    opened.book.load = async () => { throw Error('Read failed'); };
    const report = await runtime(opened).searchBook(opened.book, 'searchable', () => true);
    assert.match(report.error, /incomplete/i);
  } finally { opened.close(); }
});

test('reader appearance preserves an edition font while applying the selected text size', async () => {
  const opened = await open('<html><head/><body>Text</body></html>');
  const documentDom = new JSDOM('<html><head><style>body{font-family:EditionFace}</style></head><body>Text</body></html>');
  const viewport = new opened.dom.window.ePub.Rendition(opened.book);
  await viewport.started;
  const contents = new opened.dom.window.ePub.Contents(documentDom.window.document);
  try {
    runtime(opened).applyAppearance(viewport, 28, false);
    viewport.themes.inject(contents);
    viewport.themes.overrides(contents);
    assert.equal(documentDom.window.document.body.style.fontSize, '28px');
    assert.equal(documentDom.window.getComputedStyle(documentDom.window.document.body).fontFamily, 'EditionFace');
  } finally { contents.destroy(); documentDom.window.close(); opened.close(); }
});

module.exports = { open };
