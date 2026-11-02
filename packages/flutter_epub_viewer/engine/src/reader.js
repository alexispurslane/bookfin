function resourceFor(book, section) {
  const base = new URL(book.url.toString());
  const url = new URL(section.url, base);
  if (url.origin !== base.origin || !url.pathname.startsWith(base.pathname)) throw Error('Non-local reading resource');
  return decodeURIComponent(url.pathname.slice(base.pathname.length));
}

function quoteAt(range) {
  const document = range.startContainer.ownerDocument;
  const body = document.body || document.getElementsByTagName('body')[0];
  if (!body || !body.contains(range.startContainer)) return '';
  const after = range.cloneRange();
  after.selectNodeContents(body);
  after.setStart(range.startContainer, range.startOffset);
  return after.toString().slice(0, 120);
}

export async function visibleLocation(book, cfi, resource, displayed) {
  const collapsed = new window.ePub.CFI(cfi);
  collapsed.collapse(true);
  const start = collapsed.toString();
  const section = book.spine.get(collapsed.spinePos);
  if (!section || resourceFor(book, section) !== resource) throw Error('Location resource does not match');
  const range = await book.getRange(start);
  if (!range) throw Error('Location cannot be resolved');
  let chapter = section.document.querySelector('h1, title')?.textContent.trim() || `Chapter ${section.index + 1}`;
  let chapterCfi;
  const comparator = new window.ePub.CFI();
  for (const item of flatten(book.navigation.toc)) {
    const url = new URL(book.resolve(item.href));
    if (url.pathname !== new URL(section.url).pathname) continue;
    const target = url.hash ? section.document.getElementById(decodeURIComponent(url.hash.slice(1))) : section.document.body;
    if (!target) continue;
    const candidate = section.cfiFromElement(target);
    if (comparator.compare(candidate, start) <= 0 && (!chapterCfi || comparator.compare(candidate, chapterCfi) >= 0)) {
      chapter = item.title;
      chapterCfi = candidate;
    }
  }
  const pages = displayed && Number.isInteger(displayed.page) && Number.isInteger(displayed.total) &&
    displayed.page > 0 && displayed.total >= displayed.page ? { page: displayed.page, pages: displayed.total } : {};
  return { cfi: start, resource, quote: quoteAt(range), chapter: chapter.slice(0, 512), ...pages };
}

export async function verifyLocation(book, location) {
  const resolved = await visibleLocation(book, location.cfi, location.resource);
  if (location.quote && !resolved.quote.startsWith(location.quote)) throw Error('Saved quote does not match this document');
  return resolved;
}

export async function resolveDestination(book, href, base, packagePath) {
  const url = new URL(href, new URL(packagePath, base));
  const root = new URL(base);
  if (url.origin !== root.origin || !url.pathname.startsWith(root.pathname) || url.search) throw Error('Non-local destination');
  const section = book.spine.spineItems.find(candidate => new URL(candidate.url, root).pathname === url.pathname);
  if (!section) throw Error('Destination is not a reading-order document');
  await section.load(book.load.bind(book));
  const document = section.document;
  const target = url.hash ? document.getElementById(decodeURIComponent(url.hash.slice(1))) :
    (document.body || document.getElementsByTagName('body')[0]);
  if (!target) throw Error('Destination fragment does not exist');
  const walker = document.createTreeWalker(target, 4);
  const firstText = walker.nextNode();
  const range = document.createRange();
  if (firstText) {
    range.setStart(firstText, 0);
    range.collapse(true);
  }
  return visibleLocation(book, firstText ? section.cfiFromRange(range) : section.cfiFromElement(target), resourceFor(book, section));
}

export async function searchBook(book, query, isCurrent) {
  if (!query.trim() || query.length > 256) return { hits: [], error: 'Enter between 1 and 256 characters.' };
  const hits = [];
  let error = null;
  for (const section of book.spine.spineItems) {
    if (!isCurrent()) return { hits: [], cancelled: true, error: null };
    try {
      await section.load(book.load.bind(book));
      if (!isCurrent()) return { hits: [], cancelled: true, error: null };
      const matches = section.find(query);
      if (matches.incomplete) error = 'Search is incomplete. Only the first 500 matches per chapter are shown.';
      for (const match of matches) {
        if (hits.length >= 500) return { hits, error: 'Search is incomplete. Only the first 500 matches are shown. Use a longer phrase.' };
        hits.push({ location: await visibleLocation(book, match.cfi, resourceFor(book, section)), excerpt: match.excerpt });
      }
    } catch (_) {
      error = 'Search is incomplete. A chapter could not be searched. Retry or use Contents.';
    } finally {
      section.unload();
    }
    await new Promise(resolve => setTimeout(resolve, 0));
  }
  return { hits, error };
}

let book;
let rendition;
let settings;
let searchRequest = 0;
let searchJob = Promise.resolve();
let navigationJob = Promise.resolve();
let locationEvent = 0;

function send(name, value) {
  if (window.flutter_inappwebview) return window.flutter_inappwebview.callHandler(name, value);
}

function withNavigation(action) {
  const operation = navigationJob.catch(() => {}).then(action);
  navigationJob = operation;
  return operation;
}

function localAddress(address) {
  const url = new URL(address, settings.base);
  if (url.origin !== new URL(settings.base).origin || !url.pathname.startsWith(new URL(settings.base).pathname) ||
      url.search || url.username || url.password) throw Error('Resource request was denied');
  return url;
}

async function requestLocal(address, type) {
  const url = localAddress(address);
  const response = await fetch(url.href, { credentials: 'omit', redirect: 'error', cache: 'no-store' });
  if (!response.ok) throw Error('Local resource is unavailable');
  if (type === 'binary') return response.arrayBuffer();
  if (type === 'blob') return response.blob();
  const text = await response.text();
  if (type === 'json') return JSON.parse(text);
  if (/\.(?:xml|opf|ncx|xhtml|html|htm)$/i.test(url.pathname) || ['xml', 'xhtml', 'html', 'opf', 'ncx'].includes(type)) {
    const document = new DOMParser().parseFromString(text, 'application/xhtml+xml');
    if (document.getElementsByTagName('parsererror').length) throw Error('Local document cannot be parsed');
    return document;
  }
  return text;
}

function flatten(items, depth = 0) {
  return items.flatMap(item => [{ title: item.label.trim() || 'Untitled chapter', href: item.href, depth },
    ...flatten(item.subitems || [], Math.min(depth + 1, 16))]);
}

export async function openBook(configuration) {
  settings = configuration;
  book = window.ePub(undefined, { requestMethod: requestLocal, replacements: 'none' });
  await book.open(settings.base, 'directory');
  await book.ready;
  rendition = book.renderTo('viewer', { width: '100%', height: '100%', spread: 'none',
    flow: 'paginated', allowScriptedContent: false, allowPopups: false, method: 'write' });
  rendition.hooks.content.register(contents => {
    const document = contents.document;
    const style = document.createElement('style');
    style.textContent = '@font-face{font-family:BookfinSerif;src:url("https://bookfin-runtime.invalid/SourceSerif4.ttf")}body{overflow-wrap:break-word;line-height:1.65!important;padding:0 18px!important}img{max-width:100%!important;height:auto}a:focus{outline:2px solid currentColor}';
    document.head.appendChild(style);
    document.addEventListener('click', event => {
      const link = event.target.closest && event.target.closest('a[href]');
      if (link) {
        event.preventDefault(); event.stopImmediatePropagation();
        let href;
        try { href = new URL(link.getAttribute('href'), document.querySelector('base').href).href; } catch (_) { return; }
        go(href).catch(() => send('readerWarning', 'This internal link could not be opened. Use Contents to continue.'));
      } else if (!contents.window.getSelection().toString()) {
        send('readerTap', null);
      }
    }, true);
    let touch;
    document.addEventListener('touchstart', event => {
      if (event.touches.length === 1) touch = { x: event.touches[0].clientX, y: event.touches[0].clientY };
    }, { passive: true });
    document.addEventListener('touchend', event => {
      if (!touch || !event.changedTouches.length || contents.window.getSelection().toString()) return;
      const delta = event.changedTouches[0].clientX - touch.x;
      const vertical = event.changedTouches[0].clientY - touch.y;
      touch = null;
      if (Math.abs(delta) > 60 && Math.abs(vertical) < 50) move(delta < 0).catch(() => send('readerFailure', 'The next page could not be opened.'));
    }, { passive: true });
  });
  rendition.on('relocated', async location => {
    const sequence = ++locationEvent;
    try {
      const cfi = new window.ePub.CFI(location.start.cfi);
      const section = book.spine.get(cfi.spinePos);
      const start = await visibleLocation(book, location.start.cfi, resourceFor(book, section), location.start.displayed);
      if (sequence === locationEvent) send('readerLocation', start);
    } catch (_) {
      if (sequence === locationEvent) send('readerFailure', 'The visible reading place could not be saved. Use Contents to continue.');
    }
  });
  rendition.on('displayerror', () => send('readerFailure', 'This chapter could not be displayed. Use Contents or retry the download.'));
  await configure(settings.fontSize, settings.night, false);
  let initial;
  if (settings.initial) {
    try { initial = await verifyLocation(book, settings.initial); }
    catch (_) { send('readerWarning', 'The saved place does not match this text. Reading starts at the beginning.'); }
  }
  await rendition.display(initial ? initial.cfi : undefined);
  let entries = flatten(book.navigation.toc);
  if (!entries.length) entries = book.spine.spineItems.filter(section => section.linear).map((section, index) =>
    ({ title: `Chapter ${index + 1}`, href: section.href, depth: 0 }));
  return entries;
}

export function move(forward) { return withNavigation(() => forward ? rendition.next() : rendition.prev()); }
export function display(location) {
  return withNavigation(async () => {
    const verified = await verifyLocation(book, location);
    await rendition.display(verified.cfi);
  });
}
export function go(href) {
  return withNavigation(async () => {
    const location = await resolveDestination(book, href, settings.base, settings.packagePath);
    await rendition.display(location.cfi);
  });
}
export function applyAppearance(viewport, fontSize, night) {
  const paper = night ? '#251e19' : '#f6efe2';
  const ink = night ? '#dcc9a9' : '#39291f';
  document.body.style.backgroundColor = paper;
  viewport.themes.default({ html: { 'font-family': 'BookfinSerif, "Source Serif 4", serif' },
    body: { background: `${paper}!important`, color: `${ink}!important` },
    a: { color: `${ink}!important` } });
  viewport.themes.fontSize(`${Math.max(14, Math.min(fontSize, 96))}px`);
}
export async function configure(fontSize, night, restore = true) {
  const update = async () => {
    const current = rendition.location && rendition.location.start.cfi;
    applyAppearance(rendition, fontSize, night);
    if (restore && current) await rendition.display(current);
  };
  return restore ? withNavigation(update) : update();
}
export function search(query, request) {
  searchRequest = request;
  const operation = searchJob.catch(() => {}).then(() => searchBook(book, query, () => searchRequest === request));
  searchJob = operation;
  return operation;
}
export function cancelSearch(request) { if (searchRequest === request) searchRequest = -1; }
