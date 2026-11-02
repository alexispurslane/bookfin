const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { JSDOM } = require('jsdom');
const samples = JSON.parse(fs.readFileSync(path.resolve(__dirname, '../../../../.cache/reader-corpus/books.json')));
const engine = fs.readFileSync(path.join(__dirname, '../../assets/epub.js'), 'utf8');
const runtime = fs.readFileSync(path.join(__dirname, '../../assets/reader.js'), 'utf8');

async function open(sample) {
  const dom = new JSDOM('<html><body></body></html>', { url: 'https://bookfin-runtime.invalid/', runScripts: 'outside-only', pretendToBeVisual: true });
  dom.window.eval(engine); dom.window.eval(runtime);
  const book = dom.window.ePub(undefined, { requestMethod: async (address, type) => {
    const url = new URL(address);
    assert.ok(url.href.startsWith(sample.base), 'Only this processed publication can be requested');
    const key = decodeURIComponent(url.pathname.slice(new URL(sample.base).pathname.length));
    const bytes = fs.readFileSync(path.join(sample.directory, key));
    if (/\.(?:xml|opf|ncx|xhtml|html|htm)$/i.test(key)) return new dom.window.DOMParser().parseFromString(bytes.toString('utf8'), 'application/xhtml+xml');
    return bytes.toString('utf8');
  }});
  await book.open(sample.base, 'directory'); await book.ready;
  return { dom, book, api: dom.window.bookfinReader, close() { book.destroy(); dom.window.close(); } };
}

for (const sample of samples) test(`${sample.id}: processed contents, search, and locators survive a fresh engine`, async () => {
  const opened = await open(sample);
  let restarted;
  let view;
  try {
    const report = await opened.api.searchBook(opened.book, sample.phrase, () => true);
    assert.equal(report.error, null);
    assert.ok(report.hits.length > 0, sample.phrase);
    const location = report.hits[0].location;
    assert.ok(location.quote.toLowerCase().startsWith(sample.phrase.toLowerCase()));
    const flat = items => items.flatMap(item => [item, ...flat(item.subitems || [])]);
    for (const item of flat(opened.book.navigation.toc)) {
      const target = await opened.api.resolveDestination(opened.book, item.href, sample.base, sample.packagePath);
      assert.ok(target.cfi.startsWith('epubcfi('));
    }
    restarted = await open(sample);
    await restarted.api.verifyLocation(restarted.book, location);
    const section = restarted.book.spine.get(new restarted.dom.window.ePub.CFI(location.cfi).spinePos);
    const View = restarted.dom.window.ePub.Rendition.prototype.requireView('iframe');
    view = new View(section, { method: 'write' });
    view.create();
    restarted.dom.window.document.body.appendChild(view.element);
    await view.load(await section.render(restarted.book.load.bind(restarted.book)));
    const viewportRange = new restarted.dom.window.ePub.CFI(location.cfi).toRange(view.iframe.contentDocument);
    assert.ok(viewportRange, 'A source location must resolve inside the actual iframe document');
    const viewportCfi = view.contents.cfiFromRange(viewportRange);
    const fromViewport = await restarted.api.visibleLocation(restarted.book, viewportCfi, location.resource);
    assert.equal(fromViewport.quote, location.quote);
    await restarted.api.verifyLocation(restarted.book, fromViewport);
    const range = await restarted.book.getRange(location.cfi);
    assert.equal(range.collapsed, true);
    range.startContainer.ownerDocument.documentElement.setAttribute('style', 'font-size:36px;color:#dcc9a9');
    await restarted.api.verifyLocation(restarted.book, location);
  } finally { if (view) view.destroy(); opened.close(); if (restarted) restarted.close(); }
});
