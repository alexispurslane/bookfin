// The epub.js side of the native EPUB renderer trial (ticket boo-ju83) and
// of the fidelity check against epub.js (ticket tc-pshi). It is not a test
// of the engine and changes nothing in it.
//
// It opens each book of a plan with the built reader (assets/epub.js and
// assets/reader.js) in headless Chromium, on the WebView reader's page:
// 412 × 671 pixels, Source Serif 4 at 20 pixels (or the plan's font size).
// For each planned section it reports where each line and page starts, as
// visible character indices (reader.js `progressAt` counts the same
// characters), the place that epub.js saves for each page start (CFI,
// quote and progress, as the reader's `relocated` handler reports it), the
// time to show the section and to draw a scrub-deck page, and the quote and
// progress that epub.js gives for each CFI that the native renderer wrote.
// It saves the planned pages as PNG images. For each book it also reports
// the place of each contents entry (reader.js `resolveDestination`) and
// the hits of the plan's search phrases (reader.js `searchBook`).
//
// node trial/compare.cjs <plan.json> <publications directory> <out directory>
//
// The plan comes from test/reader/epub/trial/fidelity_test.dart. Set
// CHROME_BIN when Chromium is not in /Applications.
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const os = require('node:os');
const { spawn } = require('node:child_process');
const { once } = require('node:events');

const viewer = path.resolve(__dirname, '../..');
const root = path.resolve(viewer, '../..');
const chrome = process.env.CHROME_BIN || '/Applications/Chromium.app/Contents/MacOS/Chromium';
const assets = path.join(viewer, 'assets');
const font = fs.readFileSync(path.join(root, 'assets/fonts/SourceSerif4.ttf')).toString('base64');
const [planPath, publications, out] = process.argv.slice(2);
const width = 412;
const height = 671;

// Standard Ebooks sheets ask for hyphenation and for "pretty" line
// wrapping. Bookfin's sanitizer drops those sheets, and the trial renderer
// has neither, so the comparison turns both off. TRIAL_KEEP_WRAP=1 keeps
// them, to measure what they change.
const neutral = process.env.TRIAL_KEEP_WRAP === '1' ? '' :
  '*{hyphens:manual!important;-webkit-hyphens:manual!important;text-wrap:wrap!important}';

async function browser() {
  const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'bookfin-trial-'));
  const child = spawn(chrome, ['--headless=new', '--no-first-run', '--no-default-browser-check',
    '--remote-debugging-port=0', `--user-data-dir=${profile}`, `--window-size=${width},800`, 'about:blank'],
    { stdio: 'ignore' });
  const portFile = path.join(profile, 'DevToolsActivePort');
  const deadline = Date.now() + 20000;
  try {
    while (!fs.existsSync(portFile)) {
      if (Date.now() > deadline || child.exitCode !== null) throw Error('Headless Chromium did not start');
      await new Promise(resolve => setTimeout(resolve, 20));
    }
  } catch (error) {
    child.kill();
    fs.rmSync(profile, { recursive: true, force: true });
    throw error;
  }
  const port = fs.readFileSync(portFile, 'utf8').split('\n')[0];
  const targets = await (await fetch(`http://127.0.0.1:${port}/json`)).json();
  const socket = new WebSocket(targets.find(target => target.type === 'page').webSocketDebuggerUrl);
  await once(socket, 'open');
  let identifier = 0;
  const pending = new Map();
  socket.addEventListener('message', event => {
    const message = JSON.parse(event.data);
    if (message.id) { pending.get(message.id)(message); pending.delete(message.id); }
    if (message.method === 'Fetch.requestPaused') {
      call('Fetch.fulfillRequest', { requestId: message.params.requestId, responseCode: 200,
        responseHeaders: [{ name: 'Content-Type', value: 'font/ttf' }, { name: 'Access-Control-Allow-Origin', value: '*' }],
        body: font }).catch(() => {});
    }
  });
  async function call(method, params = {}) {
    const request = ++identifier;
    const result = new Promise(resolve => pending.set(request, resolve));
    socket.send(JSON.stringify({ id: request, method, params }));
    const message = await result;
    if (message.error || message.result.exceptionDetails) throw Error(JSON.stringify(message).slice(0, 2000));
    return message.result;
  }
  await call('Fetch.enable', { patterns: [{ urlPattern: 'https://bookfin-runtime.invalid/SourceSerif4.ttf' }] });
  await call('Emulation.setDeviceMetricsOverride', { width, height: 800, deviceScaleFactor: 2, mobile: false });
  const { product } = await call('Browser.getVersion');
  return { call, product, async evaluate(expression) {
    return (await call('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true })).result.value;
  }, async close() {
    socket.close();
    if (child.exitCode === null) { child.kill(); await once(child, 'exit'); }
    fs.rmSync(profile, { recursive: true, force: true });
  } };
}

function serve(directory) {
  const server = http.createServer((request, response) => {
    const url = decodeURIComponent(request.url.split('?')[0]);
    if (url === '/') {
      response.setHeader('Content-Type', 'text/html');
      response.end(`<!doctype html><style>html,body,#viewer{width:${width}px;height:${height}px;margin:0;overflow:hidden}</style><div id="viewer"></div><script src="/epub.js"></script><script src="/reader.js"></script>`);
      return;
    }
    if (url === '/epub.js' || url === '/reader.js') {
      response.setHeader('Content-Type', 'application/javascript');
      response.end(fs.readFileSync(path.join(assets, url.slice(1))));
      return;
    }
    const file = path.join(directory, url);
    if (!file.startsWith(directory) || !fs.existsSync(file) || !fs.statSync(file).isFile()) {
      response.writeHead(404); response.end(); return;
    }
    response.setHeader('Content-Type', /\.(?:html|xhtml|xml|opf|ncx)$/.test(file) ? 'application/xhtml+xml' :
      file.endsWith('.css') ? 'text/css' : /\.jpe?g$/.test(file) ? 'image/jpeg' : /\.png$/.test(file) ? 'image/png' :
      'application/octet-stream');
    // The admitted documents name the reader's own hosts in their
    // Content-Security-Policy, which would block this server's style
    // sheets and images. The policy is in the head, so the body and its
    // CFIs stay the same.
    if (/\.x?html$/.test(file)) {
      response.end(fs.readFileSync(file, 'utf8').replace(/<meta http-equiv="Content-Security-Policy"[^>]*\/>/, ''));
      return;
    }
    response.end(fs.readFileSync(file));
  });
  server.listen(0, '127.0.0.1');
  return server;
}

// The in-page measurement of the shown section: the visible character
// index of each line start, by page. A character starts a line when it is
// on another page than the character before it, or below it.
const measure = `(() => {
  const view = trialRendition.manager.views.first();
  const doc = view.contents.document;
  const delta = trialRendition.manager.layout.delta;
  const walker = doc.createTreeWalker(doc.body, NodeFilter.SHOW_TEXT);
  const range = doc.createRange();
  const pages = [];
  let visible = 0;
  let previous = null;
  for (let node = walker.nextNode(); node; node = walker.nextNode()) {
    const data = node.data;
    for (let index = 0; index < data.length; index++) {
      if (/\\s/.test(data[index])) continue;
      range.setStart(node, index);
      range.setEnd(node, index + 1);
      const rects = range.getClientRects();
      if (rects.length) {
        const rect = rects[0];
        const page = Math.floor((rect.left + rect.width / 2) / delta);
        if (!previous || page !== previous.page || rect.top >= previous.bottom - 1) {
          (pages[page] ||= []).push(visible);
        }
        previous = { page, bottom: rect.bottom };
      }
      visible++;
    }
  }
  const total = trialRendition.currentLocation().start.displayed.total;
  return { total, pages: Array.from({ length: Math.max(total, pages.length) }, (_, index) => pages[index] || []) };
})()`;

async function main() {
  const plan = JSON.parse(fs.readFileSync(planPath, 'utf8'));
  fs.mkdirSync(out, { recursive: true });
  const results = [];
  let chromium;
  for (const entry of plan) {
    const directory = path.resolve(publications, entry.book);
    const server = serve(directory);
    await once(server, 'listening');
    const page = await browser();
    chromium = page.product;
    const url = `http://127.0.0.1:${server.address().port}/`;
    try {
      await page.call('Page.navigate', { url });
      await page.evaluate("new Promise(resolve => { if (window.bookfinReader) resolve(); else addEventListener('load', resolve, { once: true }); })");
      await page.evaluate(`window.flutter_inappwebview = { callHandler: () => {} };
        window.bookfinPages = { postMessage: () => {} };
        const create = ePub;
        window.ePub = Object.assign((...args) => {
          const book = create(...args);
          window.trialBook = book;
          const render = book.renderTo.bind(book);
          book.renderTo = (...args) => {
            const made = render(...args);
            if (!window.trialRendition) window.trialRendition = made;
            made.hooks.content.register(contents => {
              const style = contents.document.createElement('style');
              style.textContent = ${JSON.stringify(neutral)};
              contents.document.head.appendChild(style);
            });
            return made;
          };
          return book;
        }, create);
        bookfinReader.openBook({ base: ${JSON.stringify(url)}, packagePath: ${JSON.stringify(entry.packagePath)},
          fontSize: ${entry.fontSize || 20}, night: false, initial: null })
          .then(entries => { window.trialContents = entries; return true; })`);
      const sections = [];
      for (const section of entry.sections) {
        const shown = await page.evaluate(`(async () => {
          const start = performance.now();
          await bookfinReader.seek(${section.index}, 0);
          return performance.now() - start;
        })()`);
        // A second show of the same section, as the scrub deck's hidden
        // rendition does, without the first load of its files.
        const again = await page.evaluate(`(async () => {
          const start = performance.now();
          await bookfinReader.seek(${section.index}, 0.5);
          await bookfinReader.seek(${section.index}, 0);
          return (performance.now() - start) / 2;
        })()`);
        const lines = await page.evaluate(measure);
        const cfis = [];
        const saved = [];
        const images = {};
        const wanted = new Set(section.screenshots);
        const limit = Math.min(lines.total, section.cfiPages);
        for (let number = 0; number < Math.max(limit, Math.max(-1, ...section.screenshots) + 1); number++) {
          if (number > 0) await page.evaluate('bookfinReader.move(true)');
          // The place that the reader's `relocated` handler saves for the
          // shown page: visibleLocation of the page start.
          const location = await page.evaluate(`(async () => {
            const location = trialRendition.currentLocation();
            const cfi = new ePub.CFI(location.start.cfi);
            cfi.collapse(true);
            const shown = await bookfinReader.visibleLocation(trialBook, location.start.cfi,
              ${JSON.stringify(section.resource)}, location.start.displayed);
            return { cfi: cfi.toString(), page: location.start.displayed.page, shown };
          })()`);
          if (number < limit) {
            cfis.push(location.cfi);
            // The visible character index of the shown page's first line,
            // or null for a page without text.
            const start = lines.pages[location.page - 1]?.[0] ?? null;
            saved.push({ page: location.page, start, cfi: location.shown.cfi,
              quote: location.shown.quote, progress: location.shown.progress });
          }
          if (wanted.has(number)) {
            await new Promise(resolve => setTimeout(resolve, 100));
            const shot = await page.call('Page.captureScreenshot', { format: 'png',
              clip: { x: 0, y: 0, width, height, scale: 1 } });
            const name = `${entry.book}-${section.index}-${number}.png`;
            fs.writeFileSync(path.join(out, name), Buffer.from(shot.data, 'base64'));
            images[number] = name;
          }
        }
        // The quote and progress that epub.js gives for each CFI that the
        // trial renderer wrote for a page start.
        const resolved = await page.evaluate(`(async () => {
          const resource = ${JSON.stringify(section.resource)};
          const out = [];
          for (const cfi of ${JSON.stringify(section.nativeCfis)}) {
            try {
              const location = await bookfinReader.visibleLocation(trialBook, cfi, resource, { page: 1, total: 1 });
              out.push({ cfi, quote: location.quote, progress: location.progress });
            } catch (error) { out.push({ cfi, error: String(error) }); }
          }
          return out;
        })()`);
        // The scrub deck's page drawing: the hidden rendition lays out and
        // draws a page into a JPEG.
        const previews = [];
        for (const [request, progress] of [[1, 0], [2, 0.5], [3, 0.9]]) {
          previews.push(await page.evaluate(`(async () => {
            const start = performance.now();
            try {
              await bookfinReader.previewPage(${section.index * 10 + request}, ${section.index}, ${progress}, ${width * 2.625});
            } catch (error) {
              return String(error);
            }
            return performance.now() - start;
          })()`));
        }
        sections.push({ index: section.index, showMs: shown, showAgainMs: again, previewMs: previews,
          pageCount: lines.total, lines: lines.pages, cfis, saved, resolved, images });
        process.stdout.write(`${entry.book} section ${section.index}: ${lines.total} pages, show ${shown.toFixed(0)} ms\n`);
      }
      // The place that each contents entry opens, as reader.js `go` finds
      // it, and the hits of each search phrase.
      const contents = await page.evaluate(`(async () => {
        const out = [];
        for (const item of window.trialContents) {
          try {
            const location = await bookfinReader.resolveDestination(trialBook, item.href,
              ${JSON.stringify(url)}, ${JSON.stringify(entry.packagePath)});
            out.push({ title: item.title, href: item.href, cfi: location.cfi, resource: location.resource,
              quote: location.quote });
          } catch (error) { out.push({ title: item.title, href: item.href, error: String(error) }); }
        }
        return out;
      })()`);
      const search = [];
      for (const query of entry.phrases || []) {
        search.push(await page.evaluate(`(async () => {
          const found = await bookfinReader.searchBook(trialBook, ${JSON.stringify(query)}, () => true);
          return { query: ${JSON.stringify(query)}, error: found.error, hits: found.hits.map(hit => ({
            cfi: hit.location.cfi, resource: hit.location.resource, quote: hit.location.quote,
            excerpt: hit.excerpt })) };
        })()`));
      }
      results.push({ book: entry.book, sections, contents, search });
    } finally {
      await page.close();
      server.closeAllConnections();
      await new Promise(resolve => server.close(resolve));
    }
  }
  fs.writeFileSync(path.join(out, 'chromium.json'), JSON.stringify({ chromium, books: results }, null, 1));
}

main().catch(error => { console.error(error); process.exitCode = 1; });
