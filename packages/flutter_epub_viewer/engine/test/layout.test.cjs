const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const os = require('node:os');
const { spawn } = require('node:child_process');
const { once } = require('node:events');

const engine = path.resolve(__dirname, '../..');
const root = path.resolve(engine, '../..');
const chrome = process.env.CHROME_BIN || '/Applications/Chromium.app/Contents/MacOS/Chromium';
const assets = process.env.BOOKFIN_TEST_ASSETS || path.join(engine, 'assets');
const passageFive = { cfi: 'epubcfi(/6/2!/4/26/1:0)', resource: 'OPS/one.xhtml',
  quote: 'Harbour passage 5.' };

async function browser() {
  if (!fs.existsSync(chrome)) throw Error('Set CHROME_BIN to an installed Chromium executable for real-layout tests');
  const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'bookfin-layout-'));
  const process = spawn(chrome, ['--headless=new', '--no-first-run', '--no-default-browser-check',
    '--remote-debugging-port=0', `--user-data-dir=${profile}`, '--window-size=412,800', 'about:blank'], { stdio: 'ignore' });
  const portFile = path.join(profile, 'DevToolsActivePort');
  const deadline = Date.now() + 20000;
  while (!fs.existsSync(portFile)) {
    if (Date.now() > deadline || process.exitCode !== null) throw Error('Headless Chromium did not start');
    await new Promise(resolve => setTimeout(resolve, 20));
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
  });
  async function call(method, params = {}) {
    const request = ++identifier;
    const result = new Promise(resolve => pending.set(request, resolve));
    socket.send(JSON.stringify({ id: request, method, params }));
    const message = await result;
    if (message.error || message.result.exceptionDetails) throw Error(JSON.stringify(message));
    return message.result;
  }
  return { call, async evaluate(expression) {
    return (await call('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true })).result.value;
  }, async close() {
    socket.close();
    if (process.exitCode === null) { process.kill(); await once(process, 'exit'); }
    fs.rmSync(profile, { recursive: true, force: true });
  } };
}

async function fixture({ failStyles = false, failedChapter, delayedChapter } = {}) {
  let releaseStyles;
  const styles = new Promise(resolve => { releaseStyles = resolve; });
  let requestedStyles;
  const requested = new Promise(resolve => { requestedStyles = resolve; });
  let releaseFont;
  const font = new Promise(resolve => { releaseFont = resolve; });
  let requestedFont;
  const fontRequested = new Promise(resolve => { requestedFont = resolve; });
  const paragraphs = Array.from({ length: 16 }, (_, index) => `<p>Harbour passage ${index + 1}. The reader followed the shoreline and watched the small boats return. A bookmark could keep this place while the room grew dark.</p>`).join('');
  const chapter = '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Harbour</title><link rel="stylesheet" href="book.css"/></head><body>' +
    '<h1>The quiet harbour</h1><p>This book was written for a disposable Bookfin reading test. No private library or published story is used.</p>' +
    '<p>Morning light filled the quiet harbour. Mira carried a lantern to the old reading room, where every shelf held a different journey.</p>' +
    '<p>The sepia square below is a local PNG image.</p><img src="/image.png" alt="A sepia PNG square"/><p>The next square is a local JPEG image.</p><img src="/image.png" alt="A sepia JPEG square"/>' +
    '<p><a href="two.xhtml">Visit the lantern room</a></p>' + paragraphs + '</body></html>';
  const files = {
    '/META-INF/container.xml': '<container><rootfiles><rootfile full-path="OPS/book.opf"/></rootfiles></container>',
    '/OPS/book.opf': '<package version="3.0"><metadata/><manifest><item id="one" href="one.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="one"/></spine></package>',
    '/OPS/one.xhtml': chapter,
  };
  if (failedChapter || delayedChapter) {
    files['/OPS/book.opf'] = '<package version="3.0"><metadata/><manifest><item id="one" href="one.xhtml" media-type="application/xhtml+xml"/><item id="two" href="two.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="one"/><itemref idref="two"/></spine></package>';
    for (const [name, text] of [['one', 'First chapter.'], ['two', 'Second chapter.']]) {
      files['/OPS/' + name + '.xhtml'] = '<html xmlns="http://www.w3.org/1999/xhtml"><head>' +
        (name === failedChapter ? '<link rel="stylesheet" href="missing.css"/>' :
          name === delayedChapter ? '<link rel="stylesheet" href="book.css"/>' : '') +
        '</head><body><p>' + text + '</p></body></html>';
    }
  }
  const server = http.createServer(async (request, response) => {
    if (request.url === '/') {
      response.setHeader('Content-Type', 'text/html');
      response.end('<!doctype html><style>html,body,#viewer{width:412px;height:671px;margin:0;overflow:hidden}</style><div id="viewer"></div><script src="/epub.js"></script><script src="/reader.js"></script>');
    } else if (request.url === '/OPS/book.css') {
      requestedStyles(); await styles;
      if (failStyles) { response.writeHead(404); response.end(); return; }
      response.setHeader('Content-Type', 'text/css');
      response.end('@font-face{font-family:BookSerif;src:url("/font.woff2")}body{font-family:BookSerif,serif}h1{font-size:1.5em}img{width:96px;height:96px}p{line-height:1.5}');
    } else if (request.url === '/image.png') {
      response.setHeader('Content-Type', 'image/png');
      response.end(fs.readFileSync(path.join(root, 'tool/research/readers/fixtures/dot.png')));
    } else if (request.url === '/font.woff2') {
      requestedFont(); await font;
      response.end(fs.readFileSync(path.join(root, 'docs/mockups/fonts/source-serif-4-latin.woff2')));
    } else if (request.url === '/epub.js' || request.url === '/reader.js') {
      response.setHeader('Content-Type', 'application/javascript');
      response.end(fs.readFileSync(path.join(assets, request.url.slice(1))));
    } else if (files[request.url]) {
      response.setHeader('Content-Type', 'application/xhtml+xml'); response.end(files[request.url]);
    } else { response.writeHead(404); response.end(); }
  });
  server.listen(0, '127.0.0.1'); await once(server, 'listening');
  return { url: `http://127.0.0.1:${server.address().port}/`, requested, releaseStyles, fontRequested, releaseFont,
    close() { releaseStyles(); releaseFont(); server.closeAllConnections(); return new Promise(resolve => server.close(resolve)); } };
}

async function withReader(action, resizeWhileLoading = false) {
  const source = await fixture();
  const page = await browser();
  try {
    await page.call('Page.navigate', { url: source.url });
    await page.evaluate(`new Promise(resolve => { if (window.bookfinReader) resolve(); else addEventListener('load', resolve, {once:true}); })`);
    await page.evaluate(`window.saved=[]; window.trace=[]; window.flutter_inappwebview={callHandler:(name,value)=>{trace.push({event:name,value});if(name==='readerLocation') saved.push(value)}};
      const create=window.ePub; window.ePub=Object.assign((...args)=>{const book=create(...args); const render=book.renderTo.bind(book);book.renderTo=(...args)=>{window.viewport=render(...args);for(const method of ['display','onResized','reportLocation']){const original=viewport[method].bind(viewport);viewport[method]=(...args)=>{trace.push({method,args,location:viewport.location});return original(...args)}} return viewport};return book},create);
      window.opening=bookfinReader.openBook({base:${JSON.stringify(source.url)}, packagePath:'OPS/book.opf', fontSize:20, night:false, initial:${JSON.stringify(passageFive)}}); true`);
    await source.requested;
    await page.evaluate('new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)))');
    if (resizeWhileLoading) {
      await page.evaluate("window.resizing=viewport.resize(412,667); new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)))");
      assert.equal(await page.evaluate('document.querySelectorAll("iframe").length'), 1, "Loading chapter must remain attached until resources finish");
    }
    source.releaseStyles();
    await source.fontRequested;
    source.releaseFont();
    await page.evaluate('opening');
    if (resizeWhileLoading) await page.evaluate('resizing');
    await page.evaluate(`Promise.all(viewport.getContents().map(contents=>contents.document.fonts.ready)).then(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(()=>requestAnimationFrame(resolve)))))`);
    await page.evaluate(`document.querySelector('#viewer').style.height='667px'; viewport.resize(412,667); new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(()=>requestAnimationFrame(resolve))))`);
    await page.evaluate(`new Promise(resolve=>{function ready(){const frame=document.querySelector('iframe');if(frame?.contentDocument.querySelector('link[rel=stylesheet]')?.sheet) resolve(frame.contentDocument.fonts.ready);else requestAnimationFrame(ready)}ready()}).then(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))))`);
    await page.evaluate(`viewport.reportLocation(); new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(()=>requestAnimationFrame(resolve))))`);
    await action(page);
    await page.evaluate('viewport.checkInvariants()');
  } finally { await page.close(); await source.close(); }
}

async function visiblePassage(page) {
  return page.evaluate(`(()=>{const frame=document.querySelector('iframe');const doc=frame.contentDocument;const paragraph=Array.from(doc.querySelectorAll('p')).find(element=>element.textContent.startsWith('Harbour passage 5.'));const range=doc.createRange(); range.setStart(paragraph.firstChild,0);range.setEnd(paragraph.firstChild,1);const rect=range.getBoundingClientRect();return {visibleX:rect.left+frame.getBoundingClientRect().left, visibleY:rect.top, text:paragraph.textContent, saved:saved.at(-1), frameWidth:frame.clientWidth, page:viewport.location.start.displayed};})()`);
}

function assertPassageFive(result) {
  assert.ok(result.visibleX >= 0 && result.visibleX < 412, 'Passage 5 must remain in the visible column');
  assert.ok(result.visibleY >= 0 && result.visibleY < 35, 'Passage 5 must remain the visible start');
  assert.ok(result.text.startsWith('Harbour passage 5.'));
  assert.equal(result.saved.cfi, passageFive.cfi);
  assert.ok(result.saved.quote.startsWith('Harbour passage 5.'));
  assert.equal(result.saved.page, 3);
  assert.equal(result.saved.pages, 5);
}

test('reopening retains the visible passage and saved anchor after delayed publication layout', { timeout: 30000 }, async () => {
  await withReader(async page => {
    const result = await visiblePassage(page);
    console.log('final layout', JSON.stringify(result));
    console.log('render trace', JSON.stringify(await page.evaluate('trace')));
    assertPassageFive(result);
    assert.ok((await page.evaluate('saved')).every(location => location.cfi === passageFive.cfi));
  });
});

test('fractional-pixel column geometry does not change the page label for the same visible text', { timeout: 30000 }, async () => {
  await withReader(async page => {
    assertPassageFive(await visiblePassage(page));
    await page.evaluate(`viewport.manager.views.first().element.style.transform='translateX(0.4px)'; viewport.reportLocation()`);
    assertPassageFive(await visiblePassage(page));
  });
});

test('intentional page navigation replaces the restoration anchor and survives the next resize', { timeout: 30000 }, async () => {
  await withReader(async page => {
    await page.evaluate('bookfinReader.move(true)');
    const afterNext = await page.evaluate('saved.at(-1)');
    assert.notEqual(afterNext.cfi, passageFive.cfi);
    assert.notEqual(afterNext.quote, passageFive.quote);
    await page.evaluate(`viewport.resize(412,671); viewport.q.enqueue(()=>{});`);
    await page.evaluate(`viewport.resize(412,667); viewport.q.enqueue(()=>{});`);
    const afterResize = await page.evaluate('saved.at(-1)');
    assert.equal(afterResize.cfi, afterNext.cfi);
    assert.equal(afterResize.quote, afterNext.quote);
    const visibleAnchor = await page.evaluate(`(()=>{const frame=document.querySelector('iframe');const range=new ePub.CFI(saved.at(-1).cfi).toRange(frame.contentDocument);range.setEnd(range.startContainer,range.startOffset+1);const rect=range.getBoundingClientRect();return {left:rect.left+frame.getBoundingClientRect().left,top:rect.top,text:range.startContainer.textContent.slice(range.startOffset)}})()`);
    assert.ok(visibleAnchor.left >= 0 && visibleAnchor.left < 412);
    assert.ok(visibleAnchor.top >= 0 && visibleAnchor.top < 35);
    assert.ok(visibleAnchor.text.startsWith(afterNext.quote.slice(0, 20)));
    await page.evaluate('bookfinReader.move(false)');
    assertPassageFive(await visiblePassage(page));
  });
});

test('bookmark restore and 22-pixel appearance changes retain the requested passage', { timeout: 30000 }, async () => {
  await withReader(async page => {
    await page.evaluate('bookfinReader.move(true)');
    await page.evaluate(`bookfinReader.display(${JSON.stringify(passageFive)})`);
    assertPassageFive(await visiblePassage(page));
    await page.evaluate('bookfinReader.configure(22,false)');
    assert.equal(await page.evaluate('saved.at(-1).cfi'), passageFive.cfi);
    await page.evaluate('bookfinReader.configure(20,false)');
    assertPassageFive(await visiblePassage(page));
  });
});

test('an appearance change queued after Next preserves the new reading place instead of the old one', { timeout: 30000 }, async () => {
  await withReader(async page => {
    await page.evaluate('Promise.all([bookfinReader.move(true),bookfinReader.configure(22,false)])');
    const afterNext = await page.evaluate('saved.at(-1)');
    assert.notEqual(afterNext.cfi, passageFive.cfi);
    await page.evaluate('bookfinReader.configure(20,false)');
    assert.equal(await page.evaluate('saved.at(-1).cfi'), afterNext.cfi);
  });
});

test('a failed publication stylesheet rejects opening and reports the real display failure', { timeout: 30000 }, async () => {
  const source = await fixture({ failStyles: true });
  const page = await browser();
  try {
    await page.call('Page.navigate', { url: source.url });
    await page.evaluate(`new Promise(resolve => { if (window.bookfinReader) resolve(); else addEventListener('load', resolve, {once:true}); })`);
    await page.evaluate(`window.events=[];window.flutter_inappwebview={callHandler:(name,value)=>events.push({name,value})};window.opening=bookfinReader.openBook({base:${JSON.stringify(source.url)},fontSize:20,night:false}).then(()=>({opened:true}),error=>({error:error.message}));true`);
    await source.requested;
    source.releaseStyles();
    const result = await page.evaluate('opening');
    assert.equal(result.error, 'Reading resource could not be loaded');
    const events = await page.evaluate('events');
    assert.ok(events.some(event => event.name === 'readerFailure'));
    assert.ok(!events.some(event => event.name === 'readerLocation'));
  } finally { await page.close(); await source.close(); }
});

test('resize during blocked initial resource loading keeps the requested passage attached', { timeout: 30000 }, async () => {
  await withReader(async page => {
    assert.equal(await page.evaluate('document.querySelectorAll("iframe").length'), 1);
    assertPassageFive(await visiblePassage(page));
  }, true);
});

for (const forward of [true, false]) {
  test('failed neighboring chapter resource rejects ' + (forward ? 'Next' : 'Previous'), { timeout: 30000 }, async () => {
    const source = await fixture({ failedChapter: forward ? 'two' : 'one' });
    const page = await browser();
    try {
      await page.call('Page.navigate', { url: source.url });
      await page.evaluate("new Promise(resolve => { if (window.bookfinReader) resolve(); else addEventListener('load', resolve, {once:true}); })");
      const initial = forward ? null : { cfi: 'epubcfi(/6/4!/4/2/1:0)', resource: 'OPS/two.xhtml', quote: 'Second chapter.' };
      await page.evaluate(`window.events=[];window.flutter_inappwebview={callHandler:(name,value)=>events.push({name,value})};bookfinReader.openBook({base:${JSON.stringify(source.url)},packagePath:'OPS/book.opf',fontSize:20,night:false,initial:${JSON.stringify(initial)}})`);
      const result = await page.evaluate(`bookfinReader.move(${forward}).then(()=>({completed:true}),error=>({error:error.message}))`);
      assert.equal(result.error, 'Reading resource could not be loaded');
    } finally { await page.close(); await source.close(); }
  });
}

test('automatic viewport resize waits for a loading neighboring chapter', { timeout: 30000 }, async () => {
  const source = await fixture({ delayedChapter: 'two' });
  const page = await browser();
  try {
    await page.call('Page.navigate', { url: source.url });
    await page.evaluate("new Promise(resolve => { if (window.bookfinReader) resolve(); else addEventListener('load', resolve, {once:true}); })");
    await page.evaluate(`window.saved=[];window.flutter_inappwebview={callHandler:(name,value)=>{if(name==='readerLocation')saved.push(value)}};
      const create=ePub;window.ePub=Object.assign((...args)=>{const book=create(...args);const render=book.renderTo.bind(book);book.renderTo=(...args)=>(window.viewport=render(...args));return book},create);
      bookfinReader.openBook({base:${JSON.stringify(source.url)},packagePath:'OPS/book.opf',fontSize:20,night:false})`);
    await page.evaluate('window.moving=bookfinReader.move(true);true');
    await source.requested;
    await page.evaluate("document.querySelector('#viewer').style.height='667px'; viewport.manager.onResized(); new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)))");
    assert.equal(await page.evaluate('document.querySelectorAll("iframe").length'), 1);
    source.releaseStyles();
    await source.fontRequested;
    source.releaseFont();
    await page.evaluate('moving');
    await page.evaluate('viewport.q.enqueue(()=>{})');
    assert.equal(await page.evaluate('saved.at(-1).resource'), 'OPS/two.xhtml');
    const visible = await page.evaluate(`(()=>{const frame=document.querySelector('iframe');const text=frame.contentDocument.querySelector('p');const rect=text.getBoundingClientRect();return {text:text.textContent,left:rect.left+frame.getBoundingClientRect().left,top:rect.top}})()`);
    assert.equal(visible.text, 'Second chapter.');
    assert.ok(visible.left >= 0 && visible.left < 412 && visible.top >= 0 && visible.top < 667);
    await page.evaluate('viewport.checkInvariants()');
  } finally { await page.close(); await source.close(); }
});
