const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const os = require('node:os');
const { spawn, spawnSync } = require('node:child_process');
const { once } = require('node:events');

const engine = path.resolve(__dirname, '../..');
const root = path.resolve(engine, '../..');
const chrome = process.env.CHROME_BIN || '/Applications/Chromium.app/Contents/MacOS/Chromium';
const assets = process.env.BOOKFIN_TEST_ASSETS || path.join(engine, 'assets');
const passageFive = { cfi: 'epubcfi(/6/2!/4/26/1:0)', resource: 'OPS/one.xhtml',
  quote: 'Harbour passage 5.' };

async function browser({ bookfinFont = false } = {}) {
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
    if (message.method === 'Fetch.requestPaused') {
      // A navigation cancels a font request that is still paused, such as the
      // one of the page previews that load in the background.
      call('Fetch.fulfillRequest', { requestId: message.params.requestId, responseCode: 200,
        responseHeaders: [{ name: 'Content-Type', value: 'font/ttf' }, { name: 'Access-Control-Allow-Origin', value: '*' }],
        body: fs.readFileSync(path.join(root, 'assets/fonts/SourceSerif4.ttf')).toString('base64') }).catch(() => {});
    }
  });
  async function call(method, params = {}) {
    const request = ++identifier;
    const result = new Promise(resolve => pending.set(request, resolve));
    socket.send(JSON.stringify({ id: request, method, params }));
    const message = await result;
    if (message.error || message.result.exceptionDetails) throw Error(JSON.stringify(message));
    return message.result;
  }
  if (bookfinFont) await call('Fetch.enable', { patterns: [{ urlPattern: 'https://bookfin-runtime.invalid/SourceSerif4.ttf' }] });
  return { call, async evaluate(expression) {
    return (await call('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true })).result.value;
  }, async close() {
    socket.close();
    if (process.exitCode === null) { process.kill(); await once(process, 'exit'); }
    fs.rmSync(profile, { recursive: true, force: true });
  } };
}

async function fixture({ failStyles = false, failedChapter, delayedChapter, publication, chapterMarkup, width = 412, height = 671 } = {}) {
  let releaseStyles;
  let styles = new Promise(resolve => { releaseStyles = resolve; });
  let requestedStyles;
  const requested = new Promise(resolve => { requestedStyles = resolve; });
  let releaseFont;
  const font = new Promise(resolve => { releaseFont = resolve; });
  let requestedFont;
  const fontRequested = new Promise(resolve => { requestedFont = resolve; });
  const paragraphs = Array.from({ length: 16 }, (_, index) => `<p>Harbour passage ${index + 1}. The reader followed the shoreline and watched the small boats return. A bookmark could keep this place while the room grew dark.</p>`).join('');
  const chapter = chapterMarkup || '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Harbour</title><link rel="stylesheet" href="book.css"/></head><body>' +
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
      response.end(`<!doctype html><style>html,body,#viewer{width:${width}px;height:${height}px;margin:0;overflow:hidden}</style><div id="viewer"></div><script src="/epub.js"></script><script src="/reader.js"></script>`);
    } else if (request.url === '/OPS/book.css') {
      response.setHeader('Cache-Control', 'no-store');
      requestedStyles(); await styles;
      if (failStyles) { response.writeHead(404); response.end(); return; }
      response.setHeader('Content-Type', 'text/css');
      response.end('@font-face{font-family:BookSerif;src:url("/font.woff2")}body{font-family:BookSerif,serif}h1{font-size:1.5em;margin-top:0}img{display:block;width:96px;height:96px}p{line-height:1.5}');
    } else if (request.url === '/image.png') {
      response.setHeader('Content-Type', 'image/png');
      response.end(fs.readFileSync(path.join(root, 'tool/research/readers/fixtures/dot.png')));
    } else if (request.url === '/font.woff2') {
      requestedFont(); await font;
      response.end(fs.readFileSync(path.join(root, 'docs/mockups/fonts/source-serif-4-latin.woff2')));
    } else if (request.url === '/epub.js' || request.url === '/reader.js') {
      response.setHeader('Content-Type', 'application/javascript');
      response.end(fs.readFileSync(path.join(assets, request.url.slice(1))));
    } else if (publication && fs.existsSync(path.join(publication, request.url))) {
      const resource = path.join(publication, request.url);
      response.setHeader('Content-Type', /\.(?:html|xhtml|xml|opf|ncx)$/.test(resource) ? 'application/xhtml+xml' :
        resource.endsWith('.css') ? 'text/css' : 'application/octet-stream');
      response.end(fs.readFileSync(resource));
    } else if (files[request.url] && !publication) {
      response.setHeader('Content-Type', 'application/xhtml+xml'); response.end(files[request.url]);
    } else { response.writeHead(404); response.end(); }
  });
  server.listen(0, '127.0.0.1'); await once(server, 'listening');
  return { url: `http://127.0.0.1:${server.address().port}/`, requested, releaseStyles: () => releaseStyles(), fontRequested, releaseFont,
    holdStyles() { styles = new Promise(resolve => { releaseStyles = resolve; }); return new Promise(resolve => { requestedStyles = resolve; }); },
    close() { releaseStyles(); releaseFont(); server.closeAllConnections(); return new Promise(resolve => server.close(resolve)); } };
}

for (const {name, tag, whiteSpace, text} of [
  {name: 'preformatted blank lines', tag: 'pre', whiteSpace: 'pre', text: ' ' + '\n'.repeat(60) + 'Tail'},
  {name: 'wrapped preserved blank lines', tag: 'div', whiteSpace: 'pre-wrap', text: ' ' + '\n'.repeat(60) + 'Tail'},
  {name: 'nonbreaking spaces', tag: 'div', whiteSpace: 'normal', text: '\u00a0'.repeat(400) + 'Tail'},
]) {
  test('saved whitespace remains addressable: ' + name, {timeout: 30000}, async () => {
    const source = await fixture({chapterMarkup: `<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Whitespace</title></head><body><${tag} id="target" style="white-space:${whiteSpace};line-height:30px;margin:0">${text}</${tag}></body></html>`});
    const page = await browser({bookfinFont: true});
    try {
      await page.call('Page.navigate', {url: source.url});
      await page.evaluate("new Promise(resolve => { if(window.bookfinReader)resolve();else addEventListener('load',resolve,{once:true});})");
      await page.evaluate(`window.flutter_inappwebview={callHandler:()=>{}};
        const create=ePub;window.ePub=Object.assign((...args)=>{const book=create(...args);const render=book.renderTo.bind(book);book.renderTo=(...args)=>{const made=render(...args);if(!window.shownRendition)window.viewport=window.shownRendition=made;return made};return book},create);
        bookfinReader.openBook({base:${JSON.stringify(source.url)},packagePath:'OPS/book.opf',fontSize:20,night:false,initial:null})`);
      const before = await page.evaluate(`(()=>{const contents=viewport.getContents()[0];const node=contents.document.querySelector('#target').firstChild;
        const range=contents.document.createRange();range.setStart(node,0);range.collapse(true);
        window.whitespaceAddress={cfi:contents.cfiFromRange(range),resource:'OPS/one.xhtml',quote:node.textContent.slice(0,120)};
        range.setEnd(node,1);const rect=range.getBoundingClientRect();
        const measured=contents.locationOf(whitespaceAddress.cfi);
        return {actualLeft:rect.left,actualTop:rect.top,measuredLeft:measured.left,measuredTop:measured.top,whiteSpace:contents.window.getComputedStyle(node.parentElement).whiteSpace};})()`);
      assert.equal(before.whiteSpace, whiteSpace);
      assert.ok(Math.abs(before.measuredLeft - before.actualLeft) < 1 && Math.abs(before.measuredTop - before.actualTop) < 1,
        'destination must measure the addressed whitespace, not a later word: ' + JSON.stringify(before));
      await page.evaluate('bookfinReader.display(whitespaceAddress)');
      const left = await page.evaluate(`(()=>{const frame=document.querySelector('iframe');const doc=frame.contentDocument;
        const range=doc.createRange();range.setStart(doc.querySelector('#target').firstChild,0);range.setEnd(range.startContainer,1);
        return range.getBoundingClientRect().left+frame.getBoundingClientRect().left;})()`);
      assert.ok(left >= 0 && left < 412, 'addressed whitespace must remain in the visible column');
    } finally { await page.close(); await source.close(); }
  });
}

test('converted Alice retains the recorded character passage', { timeout: 180000 }, async context => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'bookfin-kf8-layout-'));
  let source;
  let page;
  try {
    const prepared = spawnSync('flutter', ['test', '--no-pub', 'tool/reader/kf8_layout_fixture_test.dart', '--reporter', 'expanded'], {
      cwd: root, env: { ...process.env, BOOKFIN_KF8_LAYOUT_DIRECTORY: directory }, encoding: 'utf8', timeout: 90000
    });
    assert.equal(prepared.status, 0, prepared.stdout + prepared.stderr);
    const publication = JSON.parse(fs.readFileSync(path.join(directory, 'publication.json')));
    source = await fixture({ publication: path.join(directory, 'publication'), width: 412, height: 630 });
    page = await browser({ bookfinFont: true });
    const location = { cfi: 'epubcfi(/6/10!/4/2[pgepubid00003]/4/1:260)', resource: 'OEBPS/part00004.html',
      quote: ' Alice “without pictures or conversations?”\n\n\nSo she was considering in her own mind (as well as she could, for the hot ' };
    const serialized = JSON.stringify(location);
    async function open(initial = location, height = 630) {
      await page.call('Page.navigate', { url: source.url });
      await page.evaluate("new Promise(resolve => { if (window.bookfinReader) resolve(); else addEventListener('load', resolve, {once:true}); })");
      await page.evaluate(`window.saved=[];window.failures=[];window.flutter_inappwebview={callHandler:(name,value)=>{if(name==='readerLocation')saved.push(value);if(name==='readerWarning'||name==='readerFailure')failures.push(value)}};
        const create=ePub;window.ePub=Object.assign((...args)=>{const book=create(...args);const render=book.renderTo.bind(book);book.renderTo=(...args)=>{const made=render(...args);if(!window.shownRendition)window.viewport=window.shownRendition=made;return made};return book},create);
        document.querySelector('#viewer').style.height='${height}px';
        bookfinReader.openBook({base:${JSON.stringify(source.url)},packagePath:${JSON.stringify(publication.packagePath)},fontSize:22,night:false,initial:${JSON.stringify(initial)}})`);
    }
    async function assertPassage(label) {
      const visible = await page.evaluate(`(()=>{const frame=document.querySelector('iframe');const doc=frame.contentDocument;
        const paragraph=doc.querySelector('#pgepubid00003 > p');const text=paragraph.firstChild;
        const word=doc.createRange();word.setStart(text,261);word.setEnd(text,266);
        const consideration=[...doc.querySelectorAll('p')].find(element=>element.textContent.trimStart().startsWith('So she was considering'));
        const phrase=doc.createRange();phrase.setStart(consideration.firstChild,1);phrase.setEnd(consideration.firstChild,21);
        const heading=doc.querySelector('h2').getBoundingClientRect();const left=frame.getBoundingClientRect().left;
        return {word:{text:word.toString(),left:word.getBoundingClientRect().left+left,top:word.getBoundingClientRect().top},
          phrase:{text:phrase.toString(),left:phrase.getBoundingClientRect().left+left,top:phrase.getBoundingClientRect().top},
          headingLeft:heading.left+left,saved:saved.at(-1),failures,page:viewport.location.start.displayed}})()`);
      console.log(label, JSON.stringify(visible));
      assert.equal(visible.word.text, 'Alice');
      assert.equal(visible.phrase.text, 'So she was consideri');
      for (const target of [visible.word, visible.phrase]) {
        assert.ok(target.left >= 0 && target.left < 412, label + ': the saved passage must be in the visible column');
        assert.ok(target.top >= 0 && target.top < 630, label + ': the saved passage must be inside the viewport');
      }
      assert.ok(visible.headingLeft < 0, label + ': the chapter heading must be on the preceding page');
      assert.equal(visible.page.page, 2);
      assert.equal(visible.page.total, 21);
      assert.equal(visible.saved.cfi, location.cfi);
      assert.equal(visible.saved.quote, location.quote);
      assert.deepEqual(visible.failures, []);
      await page.evaluate('viewport.checkInvariants()');
    }
    await context.test('ordinary Next saves the recorded space before the visible word', async () => {
      await open(null);
      await page.evaluate("bookfinReader.go('part00004.html')");
      await page.evaluate('bookfinReader.move(true)');
      await assertPassage('ordinary Next');
    });
    await context.test('cached reopen shows the saved passage instead of the heading', async () => {
      await open();
      await assertPassage('cached reopen');
    });
    await context.test('bookmark return within a chapter shows the saved passage', async () => {
      await open(null);
      await page.evaluate("bookfinReader.go('part00004.html')");
      await page.evaluate('bookfinReader.move(true).then(()=>bookfinReader.move(true))');
      await page.evaluate(`bookfinReader.display(${serialized})`);
      await assertPassage('same-chapter bookmark');
    });
    await context.test('bookmark return from another chapter shows the saved passage', async () => {
      await open(null);
      await page.evaluate("bookfinReader.go('part00005.html')");
      await page.evaluate(`bookfinReader.display(${serialized})`);
      await assertPassage('other-chapter bookmark');
    });
    await context.test('a new browser process shows the retained passage', async () => {
      await page.close();
      page = await browser({ bookfinFont: true });
      await open(JSON.parse(serialized));
      await assertPassage('fresh browser process');
    });
    await context.test('height changes keep the saved passage visible', async () => {
      await open(location, 600);
      await page.evaluate("document.querySelector('#viewer').style.height='630px';viewport.resize(412,630);viewport.q.enqueue(()=>{})");
      await assertPassage('height restoration');
    });
    await context.test('text-size changes retain the saved passage and stored CFI', async () => {
      await open();
      await page.evaluate('bookfinReader.configure(24,false).then(()=>bookfinReader.configure(22,false))');
      await assertPassage('text-size restoration');
    });
  } finally {
    if (page) await page.close();
    if (source) await source.close();
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

async function withReader(action, resizeWhileLoading = false) {
  const source = await fixture();
  const page = await browser();
  try {
    await page.call('Page.navigate', { url: source.url });
    await page.evaluate(`new Promise(resolve => { if (window.bookfinReader) resolve(); else addEventListener('load', resolve, {once:true}); })`);
    await page.evaluate(`window.saved=[]; window.trace=[]; window.flutter_inappwebview={callHandler:(name,value)=>{trace.push({event:name,value});if(name==='readerLocation') saved.push(value)}};
      const create=window.ePub; window.ePub=Object.assign((...args)=>{const book=create(...args); const render=book.renderTo.bind(book);book.renderTo=(...args)=>{if(window.shownRendition)return render(...args);window.viewport=window.shownRendition=render(...args);for(const method of ['display','onResized','reportLocation']){const original=viewport[method].bind(viewport);viewport[method]=(...args)=>{trace.push({method,args,location:viewport.location});return original(...args)}} return viewport};return book},create);
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
    await page.evaluate(pageListener);
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
    assert.equal(await page.evaluate('viewport.manager.container.querySelectorAll("iframe").length'), 1);
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
      const create=ePub;window.ePub=Object.assign((...args)=>{const book=create(...args);const render=book.renderTo.bind(book);book.renderTo=(...args)=>{const made=render(...args);if(!window.shownRendition)window.viewport=window.shownRendition=made;return made};return book},create);
      bookfinReader.openBook({base:${JSON.stringify(source.url)},packagePath:'OPS/book.opf',fontSize:20,night:false})`);
    await page.evaluate('window.moving=bookfinReader.move(true);true');
    await source.requested;
    await page.evaluate("document.querySelector('#viewer').style.height='667px'; viewport.manager.onResized(); new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)))");
    assert.equal(await page.evaluate('viewport.manager.container.querySelectorAll("iframe").length'), 1);
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

for (const navigation of ['contents', 'bookmark']) {
  test(navigation + ' navigation cannot release a resize restoration before its resources finish', { timeout: 30000 }, async () => {
    const source = await fixture({ delayedChapter: 'one' });
    const page = await browser();
    try {
      source.releaseStyles();
      source.releaseFont();
      await page.call('Page.navigate', { url: source.url });
      await page.evaluate("new Promise(resolve => { if (window.bookfinReader) resolve(); else addEventListener('load', resolve, {once:true}); })");
      await page.evaluate(`window.saved=[];window.flutter_inappwebview={callHandler:(name,value)=>{if(name==='readerLocation')saved.push(value)}};
        const create=ePub;window.ePub=Object.assign((...args)=>{const book=create(...args);const render=book.renderTo.bind(book);book.renderTo=(...args)=>{const made=render(...args);if(!window.shownRendition)window.viewport=window.shownRendition=made;return made};return book},create);
        bookfinReader.openBook({base:${JSON.stringify(source.url)},packagePath:'OPS/book.opf',fontSize:20,night:false})`);
      const requested = source.holdStyles();
      await page.evaluate("document.querySelector('#viewer').style.height='667px';viewport.manager.onResized();true");
      await requested;
      await page.evaluate(`window.loadingFrame=document.querySelector('iframe');window.destination=${navigation === 'contents' ?
        "bookfinReader.go('two.xhtml')" :
        "bookfinReader.display({cfi:'epubcfi(/6/4!/4/2/1:0)',resource:'OPS/two.xhtml',quote:'Second chapter.'})"};
        new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(()=>requestAnimationFrame(resolve))))`);
      assert.equal(await page.evaluate('loadingFrame.isConnected'), true, 'Queued navigation must not remove the active loading chapter');
      source.releaseStyles();
      await page.evaluate('destination');
      await page.evaluate('viewport.q.enqueue(()=>{})');
      assert.equal(await page.evaluate('saved.at(-1).resource'), 'OPS/two.xhtml');
      assert.equal(await page.evaluate("document.querySelector('iframe').contentDocument.querySelector('p').textContent"), 'Second chapter.');
      await page.evaluate('viewport.checkInvariants()');
    } finally { await page.close(); await source.close(); }
  });
}

// The share of the section's visible characters, white space left out, that
// come before the first character of [text]. It reads the shown document, so
// it does not use the reader's own measure.
function shareBefore(text) {
  return `(()=>{const doc=document.querySelector('iframe').contentDocument;const letters=doc.body.textContent.replace(/\\s/g,'');
    return letters.indexOf(${JSON.stringify(text)}.replace(/\\s/g,''))/letters.length})()`;
}

test('a reported place carries its text progress through its section', { timeout: 30000 }, async () => {
  await withReader(async page => {
    const expected = await page.evaluate(shareBefore('Harbour passage 5.'));
    assert.ok(expected > 0.2 && expected < 0.8, 'passage 5 sits inside the section: ' + expected);
    assert.ok(Math.abs((await page.evaluate('saved.at(-1).progress')) - expected) < 1e-5);
    await page.evaluate('bookfinReader.move(true)');
    assert.ok((await page.evaluate('saved.at(-1).progress')) > expected, 'Next moves the progress on');
  });
});

test('seeking to a text progress shows the page that holds it', { timeout: 30000 }, async () => {
  await withReader(async page => {
    const passage = await page.evaluate(shareBefore('Harbour passage 5.'));
    await page.evaluate('bookfinReader.move(true)');
    await page.evaluate(`bookfinReader.seek(0, ${passage})`);
    assertPassageFive(await visiblePassage(page));
    await page.evaluate('bookfinReader.seek(0, 0)');
    assert.equal(await page.evaluate('saved.at(-1).page'), 1);
    assert.equal(await page.evaluate('saved.at(-1).progress'), 0);
    await page.evaluate('bookfinReader.seek(0, 1)');
    assert.equal(await page.evaluate('saved.at(-1).page'), 5, 'The end of a section is its last page');
    await assert.rejects(page.evaluate('bookfinReader.seek(4, 0)'));
  });
});

// The mean difference of two images, drawn at one small size, per color
// channel from 0 to 255.
function imageDifference(first, second) {
  return `(async()=>{const load=async source=>{const image=new Image();image.src=source;await image.decode();return image};
    const images=await Promise.all([load(${JSON.stringify(first)}),load(${JSON.stringify(second)})]);
    const [a,b]=images.map(image=>{const canvas=document.createElement('canvas');canvas.width=103;canvas.height=167;
      const context=canvas.getContext('2d');context.drawImage(image,0,0,103,167);return context.getImageData(0,0,103,167).data});
    let sum=0;for(let index=0;index<a.length;index+=4)for(let channel=0;channel<3;channel++)sum+=Math.abs(a[index+channel]-b[index+channel]);
    return sum/(a.length/4*3)})()`;
}

// Stands in for the app's page listener. `previewOf(index, progress, width)`
// draws a page with the next request number and returns its report, with the
// posted image as a JPEG data URL and the request number that the image
// carried.
const pageListener = `window.posted=[];window.previewCount=0;window.bookfinPages={postMessage:buffer=>posted.push(buffer)};
  window.previewOf=async(index,progress,width)=>{const request=++previewCount;const report=await bookfinReader.previewPage(request,index,progress,width);
    const bytes=new Uint8Array(posted.at(-1));const blob=new Blob([bytes.subarray(4)],{type:'image/jpeg'});
    const image=await new Promise(resolve=>{const reader=new FileReader();reader.onload=()=>resolve(reader.result);reader.readAsDataURL(blob)});
    return {...report,image,tag:new DataView(bytes.buffer).getUint32(0,true),request,jpeg:bytes[4]===0xff&&bytes[5]===0xd8}};true`;

// The shown viewport as a PNG data URL.
async function shownPage(page) {
  await page.evaluate('new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)))');
  const shot = await page.call('Page.captureScreenshot', { format: 'png', clip: { x: 0, y: 0, width: 412, height: 667, scale: 1 } });
  return 'data:image/png;base64,' + shot.data;
}

test('a page preview draws the page at a place and leaves the shown page where it is', { timeout: 60000 }, async () => {
  await withReader(async page => {
    const passage = await page.evaluate(shareBefore('Harbour passage 5.'));
    await page.evaluate('bookfinReader.seek(0, 0)');
    const reported = await page.evaluate('saved.length');
    const preview = await page.evaluate(`previewOf(0, ${passage}, 412)`);
    assert.ok(preview.start <= passage && passage <= preview.end, 'the preview holds the place: ' + JSON.stringify({ ...preview, image: undefined }));
    assert.equal(await page.evaluate('saved.length'), reported, 'a preview reports no reading place');
    assert.equal(await page.evaluate('viewport.location.start.displayed.page'), 1, 'the shown page stays');
    const first = await shownPage(page);
    await page.evaluate(`bookfinReader.seek(0, ${passage})`);
    const target = await shownPage(page);
    const same = await page.evaluate(imageDifference(preview.image, target));
    const other = await page.evaluate(imageDifference(preview.image, first));
    assert.ok(same < 6, 'the preview looks like the page itself: ' + same);
    assert.ok(other > same * 2, 'the preview differs from another page: ' + JSON.stringify({ same, other }));
  });
});

test('opening a book prepares the page previews in the background, beside the shown page', { timeout: 60000 }, async () => {
  await withReader(async page => {
    const frames = await page.evaluate(`new Promise(resolve=>{const started=performance.now();(function check(){const count=document.querySelectorAll('iframe').length;
      if(count>1||performance.now()-started>10000)resolve(count);else setTimeout(check,50)})()})`);
    assert.equal(frames, 2, 'the hidden rendition has its own frame');
    assertPassageFive(await visiblePassage(page));
  });
});

test('a page preview posts its image as raw JPEG bytes that carry its request number', { timeout: 60000 }, async () => {
  await withReader(async page => {
    const preview = await page.evaluate('previewOf(0, 0, 206)');
    assert.ok(preview.jpeg, 'the bytes after the number are a JPEG image');
    assert.equal(preview.tag, preview.request);
    assert.equal(preview.image.startsWith('data:image/jpeg;base64,'), true);
    assert.equal(await page.evaluate('posted.length'), 1, 'one message for one page');
  });
});

test('a cancelled page preview stops and posts no image', { timeout: 60000 }, async () => {
  await withReader(async page => {
    const outcome = await page.evaluate(`(async()=>{const drawing=bookfinReader.previewPage(7,0,0.5,206);bookfinReader.cancelPreview(7);
      try{await drawing;return 'drawn'}catch(error){return error.message}})()`);
    assert.equal(outcome, 'The preview was cancelled');
    assert.equal(await page.evaluate('posted.length'), 0);
  });
});

test('cancelling a page preview that ended leaves the next preview alone', { timeout: 60000 }, async () => {
  await withReader(async page => {
    await page.evaluate('previewOf(0, 0, 103)');
    await page.evaluate('bookfinReader.cancelPreview(previewCount)');
    const next = await page.evaluate('previewOf(0, 0.5, 103)');
    assert.ok(next.jpeg);
    assert.equal(next.tag, 2);
  });
});

test('a page preview names where its neighbors start, and the book ends have none', { timeout: 60000 }, async () => {
  await withReader(async page => {
    const first = await page.evaluate('previewOf(0, 0, 103)');
    assert.equal(first.previous, null);
    assert.equal(first.start, 0);
    assert.equal(first.next.part, 0);
    assert.ok(first.next.progress > first.end, JSON.stringify({ ...first, image: undefined }));
    const second = await page.evaluate(`previewOf(0, ${first.next.progress}, 103)`);
    assert.ok(second.start > first.end - 1e-6 && second.start <= first.next.progress);
    const back = await page.evaluate(`previewOf(0, ${second.previous.progress}, 103)`);
    assert.equal(back.start, first.start);
    const last = await page.evaluate('previewOf(0, 1, 103)');
    assert.equal(last.next, null);
    assert.equal(last.end, 1);
  });
});

test('a page preview follows the reading appearance as it changes, and its scale', { timeout: 60000 }, async () => {
  await withReader(async page => {
    await page.evaluate('previewOf(0, 0, 206)');
    await page.evaluate('bookfinReader.configure(20, true)');
    const preview = await page.evaluate('previewOf(0, 0, 206)');
    const pixel = await page.evaluate(`(async()=>{const image=new Image();image.src=${JSON.stringify(preview.image)};await image.decode();
      const canvas=document.createElement('canvas');canvas.width=image.width;canvas.height=image.height;const context=canvas.getContext('2d');
      context.drawImage(image,0,0);return {width:image.width,height:image.height,corner:[...context.getImageData(2,2,1,1).data]}})()`);
    assert.equal(pixel.width, 206);
    assert.equal(pixel.height, 334);
    assert.ok(pixel.corner.slice(0, 3).every(channel => channel < 70), 'the night paper is dark: ' + pixel.corner);
  });
});

test('a page preview crosses from a section to its neighbors', { timeout: 60000 }, async () => {
  const source = await fixture({ delayedChapter: 'two' });
  const page = await browser();
  try {
    source.releaseStyles();
    source.releaseFont();
    await page.call('Page.navigate', { url: source.url });
    await page.evaluate("new Promise(resolve => { if (window.bookfinReader) resolve(); else addEventListener('load', resolve, {once:true}); })");
    await page.evaluate(`window.flutter_inappwebview={callHandler:()=>{}};
      bookfinReader.openBook({base:${JSON.stringify(source.url)},packagePath:'OPS/book.opf',fontSize:20,night:false})`);
    await page.evaluate(pageListener);
    const end = await page.evaluate('previewOf(0, 1, 103)');
    assert.deepEqual(end.next, { part: 1, progress: 0 });
    const start = await page.evaluate('previewOf(1, 0, 103)');
    assert.equal(start.part, 1);
    assert.deepEqual(start.previous, { part: 0, progress: 1 });
    assert.equal(start.next, null);
    assert.equal(await page.evaluate("document.querySelector('iframe').contentDocument.querySelector('p').textContent"), 'First chapter.',
      'the shown page stays in its section');
  } finally { await page.close(); await source.close(); }
});

test('a section without a doctype lays out in standards mode, as XHTML does', { timeout: 30000 }, async () => {
  await withReader(async page => {
    assert.equal(await page.evaluate("document.querySelector('iframe').contentDocument.compatMode"), 'CSS1Compat');
  });
});
