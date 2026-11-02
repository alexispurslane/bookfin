const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { test } = require('node:test');
const { JSDOM } = require('jsdom');

const root = path.resolve(__dirname, '../../../..');
const work = path.join(root, '.cache/navigator');
const scripts = path.join(work, 'sources/flutter_epub_viewer/lib/assets/webpage');
const books = JSON.parse(fs.readFileSync(path.join(work, 'books.json')));
const observations = [];

async function openBook(sample) {
  const dom = new JSDOM('<html><body><div id="viewer"></div></body></html>', {
    url: 'https://bookfin.invalid/reader', runScripts: 'outside-only',
  });
  for (const name of ['dist/jszip.min.js', 'dist/epub.js', 'html/epub_cfi_utils.js', 'html/epubView.js']) {
    const source = name === 'dist/epub.js' && process.env.NAVIGATOR_ENGINE === 'upstream'
      ? path.join(work, 'sources/epubjs/dist/epub.js') : path.join(scripts, name);
    dom.window.eval(fs.readFileSync(source, 'utf8'));
  }
  const base = 'https://bookfin.invalid/publication/';
  const directory = path.join(root, sample.directory);
  const requests = [];
  const request = async (href, type) => {
    const url = new URL(href, base);
    assert.equal(url.origin, 'https://bookfin.invalid');
    assert.ok(url.pathname.startsWith('/publication/'));
    const relative = decodeURIComponent(url.pathname.slice('/publication/'.length));
    const filename = path.resolve(directory, relative);
    assert.ok(filename.startsWith(directory + path.sep));
    requests.push(relative);
    const content = fs.readFileSync(filename, 'utf8');
    const responseType = type || path.extname(filename).slice(1);
    if (['xml', 'xhtml', 'html', 'opf', 'ncx'].includes(responseType)) {
      return new dom.window.DOMParser().parseFromString(content, responseType === 'html' ? 'text/html' : 'application/xml');
    }
    return content;
  };
  dom.window.book = dom.window.ePub(undefined, { requestMethod: request });
  await dom.window.book.open(base, 'directory');
  await dom.window.book.ready;
  return { dom, book: dom.window.book, requests };
}

function flattenContents(items) {
  return items.flatMap(item => [item, ...flattenContents(item.subitems || [])]);
}

for (const sample of books) {
  test(`${sample.id}: source contents resolve and search positions survive styling and reopen`, async () => {
    const opened = await openBook(sample);
    let reopened;
    try {
      const contents = flattenContents(opened.book.navigation.toc);
      assert.ok(opened.book.spine.length > 0, 'The EPUB must expose reading-order resources');
      for (const item of contents) {
        assert.ok(opened.book.spine.get(item.href), `Contents link not in spine: ${item.href}`);
      }
      const hits = await opened.dom.window.searchInBook(sample.phrase);
      assert.ok(hits.length > 0, `Missing search phrase: ${sample.phrase}`);
      const first = hits[0];
      assert.match(first.cfi, /^epubcfi\(/);
      const range = await opened.book.getRange(first.cfi);
      assert.equal(range.toString().toLocaleLowerCase(), sample.phrase.toLocaleLowerCase());
      const document = range.startContainer.ownerDocument;
      document.documentElement.style.fontSize = '28px';
      document.body.style.color = '#e6d7c1';
      document.body.style.backgroundColor = '#241b17';
      const styledRange = await opened.book.getRange(first.cfi);
      assert.equal(styledRange.toString(), range.toString());
      reopened = await openBook(sample);
      const restoredRange = await reopened.book.getRange(first.cfi);
      assert.equal(restoredRange.toString(), range.toString());
      observations.push({
        id: sample.id, engine: process.env.NAVIGATOR_ENGINE || 'bundled', spine_resources: opened.book.spine.length,
        contents_links: contents.length, query: sample.phrase, hits: hits.length,
        needs_spine_menu_fallback: contents.length === 0,
        cfi: first.cfi, restored_text: restoredRange.toString(),
        source_sha256: sample.source_sha256, epub_sha256: sample.epub_sha256,
        requested_resources: [...new Set(opened.requests)],
        scope: 'DOM only: no layout, pagination, WebView, TalkBack, or Android persistence result',
      });
    } finally {
      opened.book.destroy();
      opened.dom.window.close();
      if (reopened) {
        reopened.book.destroy();
        reopened.dom.window.close();
      }
    }
  });
}

test('semantic EPUB retains headings, language, local note targets and the embedded font association', async () => {
  const sample = books.find(book => book.id === 'semantic-epub3');
  const opened = await openBook(sample);
  try {
    const first = opened.book.spine.get('Text/one.xhtml');
    await first.load(opened.book.load.bind(opened.book));
    assert.equal(first.document.querySelector('h1').textContent, 'Édition stable');
    assert.equal(first.document.querySelector('[dir="rtl"]').textContent, 'كتاب');
    assert.equal(first.document.querySelector('img').getAttribute('alt'), 'A sepia square');
    assert.equal(first.document.querySelector('link').getAttribute('href'), '../Styles/book.css');
    const note = opened.book.spine.get('Text/two.xhtml#note');
    await note.load(opened.book.load.bind(opened.book));
    assert.equal(note.document.getElementById('note').querySelector('p').textContent, 'A local footnote.');
    const inlineHits = await opened.dom.window.searchInBook('crosses inline emphasis');
    const repeatedHits = await opened.dom.window.searchInBook('Repeatable phrase');
    const adjacentHits = await opened.dom.window.searchInBook('source position');
    assert.ok(adjacentHits.length > 0);
    if (process.env.NAVIGATOR_REQUIRE_INLINE_SEARCH === '1') {
      assert.ok(inlineHits.length > 0, 'A visible phrase must remain searchable across inline emphasis');
      assert.equal((await opened.book.getRange(inlineHits[0].cfi)).toString(), 'crosses inline emphasis');
    }
    assert.equal((await opened.book.getRange(adjacentHits[0].cfi)).toString(), 'source position');
    const searchEvidence = process.env.NAVIGATOR_ENGINE === 'upstream'
      ? process.env.NAVIGATOR_REQUIRE_INLINE_SEARCH === '1' ? 'inline-search-upstream-patched.json' : 'inline-search-upstream.json'
      : process.env.NAVIGATOR_REQUIRE_INLINE_SEARCH === '1' ? 'inline-search-patched.json' : 'inline-search.json';
    fs.writeFileSync(path.join(root, 'tool/research/readers/evidence/navigator', searchEvidence),
      JSON.stringify({query: 'crosses inline emphasis', hits: inlineHits.length,
        repeated_query: 'Repeatable phrase', repeated_hits: repeatedHits.length,
        source: 'A phrase crosses <em>inline emphasis</em> in this sentence.',
        scope: 'Observation of the bundled wrapper search; not acceptance of missing results.'}, null, 2) + '\n');
    if (process.env.NAVIGATOR_REQUIRE_COMPLETE_SEARCH === '1') {
      assert.equal(repeatedHits.length, 2, 'Search must return both repeated occurrences in one paragraph');
    }
  } finally {
    opened.book.destroy();
    opened.dom.window.close();
  }
});

test.after(() => {
  if (observations.length > 0) {
    const filename = process.env.NAVIGATOR_ENGINE === 'upstream'
      ? process.env.NAVIGATOR_REQUIRE_INLINE_SEARCH === '1' ? 'dom-observations-upstream-patched.json' : 'dom-observations-upstream.json'
      : process.env.NAVIGATOR_REQUIRE_INLINE_SEARCH === '1' ? 'dom-observations-patched.json' : 'dom-observations.json';
    fs.writeFileSync(path.join(root, 'tool/research/readers/evidence/navigator', filename),
      JSON.stringify(observations, null, 2) + '\n');
  }
});
