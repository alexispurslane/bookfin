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

const visibleLength = text => text.replace(/\s/g, '').length;

// The text progress of a range through its section: the share of the visible
// characters of the section's body, white space left out, that come before
// the range. Bookfin's book map measures chapter starts the same way.
function progressAt(range) {
  const document = range.startContainer.ownerDocument;
  const body = document.body || document.getElementsByTagName('body')[0];
  if (!body || !body.contains(range.startContainer)) return 0;
  const total = visibleLength(body.textContent);
  if (!total) return 0;
  const before = range.cloneRange();
  before.selectNodeContents(body);
  before.setEnd(range.startContainer, range.startOffset);
  return Math.round(visibleLength(before.toString()) / total * 1e6) / 1e6;
}

// The start of the visible character at text progress [progress] through
// [section], which must be loaded. A section with no text has its start.
function placeAt(section, progress) {
  const document = section.document;
  const body = document.body || document.getElementsByTagName('body')[0];
  const total = body ? visibleLength(body.textContent) : 0;
  if (!total) return section.href;
  let wanted = Math.min(total - 1, Math.floor(progress * total));
  const walker = document.createTreeWalker(body, NodeFilter.SHOW_TEXT | NodeFilter.SHOW_CDATA_SECTION);
  for (let node = walker.nextNode(); node; node = walker.nextNode()) {
    const count = visibleLength(node.data);
    if (wanted >= count) { wanted -= count; continue; }
    let offset = 0;
    for (; offset < node.data.length; offset++) if (!/\s/.test(node.data[offset]) && wanted-- === 0) break;
    const range = document.createRange();
    range.setStart(node, offset);
    range.collapse(true);
    return section.cfiFromRange(range);
  }
  return section.href;
}

// The saved form of the place at [cfi]. A shown place, which comes with the
// page that [displayed] reports, also carries its page and its text progress.
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
  const progress = displayed ? { progress: progressAt(range) } : {};
  return { cfi: start, resource, quote: quoteAt(range), chapter: chapter.slice(0, 512), ...pages, ...progress };
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

// The reader's own style in each shown section, which the page previews
// share.
function addReaderStyle(document) {
  const style = document.createElement('style');
  style.textContent = '@font-face{font-family:BookfinSerif;src:url("https://bookfin-runtime.invalid/SourceSerif4.ttf")}body{overflow-wrap:break-word;line-height:1.65!important;padding:0 18px!important}img{max-width:100%!important;height:auto}a:focus{outline:2px solid currentColor}';
  document.head.appendChild(style);
}

const renditionOptions = { width: '100%', height: '100%', spread: 'none',
  flow: 'paginated', allowScriptedContent: false, allowPopups: false, method: 'write' };

let book;
let rendition;
let settings;
// The text size and theme that the shown page uses, which the page previews
// follow.
let appearance;
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
  rendition = book.renderTo('viewer', renditionOptions);
  rendition.hooks.content.register(contents => {
    const document = contents.document;
    addReaderStyle(document);
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
// Shows the page that holds the place [progress] of the way through the text
// of spine section [index], from 0 at its start to 1 at its end.
export function seek(index, progress) {
  return withNavigation(async () => {
    const section = Number.isInteger(index) && book.spine.get(index);
    if (!section || typeof progress !== 'number' || !(progress >= 0 && progress <= 1)) throw Error('The destination is not in this book');
    await section.load(book.load.bind(book));
    await rendition.display(placeAt(section, progress));
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
    appearance = { fontSize, night };
    applyAppearance(rendition, fontSize, night);
    if (preview) applyAppearance(preview, fontSize, night);
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

// The page previews of the scrub deck. A second rendition of the same book
// lays out pages in a hidden box of the shown page's size, with the shown
// page's appearance, so its pages break where the shown pages break. It draws
// a page into an image without moving the shown page or reporting a place.
let preview;
let previewJob = Promise.resolve();
// Each publication resource that a drawn page uses, as a data URL, by its
// address. A drawn page is an image, which cannot load anything itself.
const inlined = new Map();

function previewRendition() {
  if (preview) return preview;
  // The box fills the shown page's own box, so both have one size.
  const viewer = document.getElementById('viewer');
  if (getComputedStyle(viewer).position === 'static') viewer.style.position = 'relative';
  // epub.js makes its frames visible, which would undo `visibility: hidden`
  // on the box. No child can undo the box's opacity.
  const box = document.createElement('div');
  box.inert = true;
  box.setAttribute('aria-hidden', 'true');
  box.style.cssText = 'position:absolute;left:0;top:0;width:100%;height:100%;opacity:0;z-index:-1;pointer-events:none';
  viewer.appendChild(box);
  preview = book.renderTo(box, renditionOptions);
  preview.hooks.content.register(contents => addReaderStyle(contents.document));
  applyAppearance(preview, appearance.fontSize, appearance.night);
  return preview;
}

function dataUrl(blob) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result);
    reader.onerror = () => reject(reader.error);
    reader.readAsDataURL(blob);
  });
}

// [address] as a data URL. Only the reader's font and the publication's own
// resources are read.
function inline(address) {
  if (!inlined.has(address)) {
    const url = new URL(address);
    const job = url.origin === 'https://bookfin-runtime.invalid' && url.pathname === '/SourceSerif4.ttf'
      ? fetch(url.href, { credentials: 'omit', redirect: 'error' }).then(response => response.blob())
      : requestLocal(url.href, 'blob');
    inlined.set(address, job.then(dataUrl).catch(() => ''));
  }
  return inlined.get(address);
}

// [css] with each url() that it names replaced by its data URL, resolved
// against [base].
// Each style text with its resources inlined, by its base and its text. A
// book has a few style texts, and every page of a section shares them.
const inlinedCss = new Map();

function inlineCss(css, base) {
  const key = base + '\n' + css;
  if (!inlinedCss.has(key)) inlinedCss.set(key, inlineCssOnce(css, base));
  return inlinedCss.get(key);
}

async function inlineCssOnce(css, base) {
  const pattern = /url\(\s*(['"]?)([^'")]+)\1\s*\)/g;
  const addresses = new Set();
  for (const [, , address] of css.matchAll(pattern)) {
    if (!address.startsWith('data:')) addresses.add(new URL(address, base).href);
  }
  const found = new Map(await Promise.all([...addresses].map(async address => [address, await inline(address)])));
  return css.replace(pattern, (whole, quote, address) => address.startsWith('data:') ? whole :
    `url("${found.get(new URL(address, base).href) || ''}")`);
}

// The style of [document] as one text: its own style elements and its linked
// style sheets, in order, each with its resources inlined.
async function documentCss(document) {
  const parts = await Promise.all([...document.querySelectorAll('style, link[rel~="stylesheet"]')].map(async node => {
    // epub.js adds its theme rules to a style element's sheet, not its text.
    if (node.localName === 'style') {
      const rules = node.sheet ? [...node.sheet.cssRules].map(rule => rule.cssText).join('\n') : node.textContent;
      return inlineCss(rules, document.baseURI);
    }
    const address = new URL(node.getAttribute('href'), document.baseURI).href;
    if (!linkedCss.has(address)) {
      linkedCss.set(address, requestLocal(address, 'text').then(css => inlineCss(css, address), () => ''));
    }
    return linkedCss.get(address);
  }));
  return parts.join('\n');
}

// Each linked style sheet with its resources inlined, by its address.
const linkedCss = new Map();

const encodedCss = new Map();

// Draws the shown page of [view] into a JPEG data URL, [scale] image pixels
// for each layout pixel. The page's document, with its style and resources
// inlined, becomes an SVG image, which the browser draws as it draws the page.
async function drawPage(view, scale) {
  const manager = view.manager;
  const frame = manager.views.first();
  const document = frame.contents.document;
  const width = manager.container.clientWidth;
  const height = manager.container.clientHeight;
  const left = manager.container.scrollLeft - frame.element.offsetLeft;
  const css = await documentCss(document);
  // The style, with the reader's font, is most of the image's text. It is
  // the same for each page of a book, so it is encoded once.
  if (!encodedCss.has(css)) encodedCss.set(css, encodeURIComponent(css));
  const clone = document.documentElement.cloneNode(true);
  for (const node of clone.querySelectorAll('style, link, script')) node.remove();
  // In a shown section, the body's overflow passes to the frame, which is as
  // wide as all the columns. In the image, the body would clip its columns.
  for (const element of [clone, clone.querySelector('body')]) element?.style.setProperty('overflow', 'visible', 'important');
  await Promise.all([...clone.querySelectorAll('img[src], image')].map(async image => {
    const attribute = image.localName === 'img' ? 'src' : image.hasAttribute('href') ? 'href' : 'xlink:href';
    const value = image.getAttribute(attribute);
    if (value && !value.startsWith('data:')) image.setAttribute(attribute, await inline(new URL(value, document.baseURI).href));
  }));
  const marker = 'bookfin-preview-style';
  const style = document.createElementNS('http://www.w3.org/1999/xhtml', 'style');
  style.textContent = marker;
  (clone.querySelector('head') || clone).prepend(style);
  const [before, after] = new XMLSerializer().serializeToString(clone).split(marker);
  const frameWidth = frame.element.offsetWidth;
  const head = `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}"><foreignObject x="${-left}" y="0" width="${frameWidth}" height="${height}">`;
  const image = new Image();
  image.src = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(head + before) + encodedCss.get(css) +
    encodeURIComponent(after + '</foreignObject></svg>');
  await image.decode();
  const canvas = window.document.createElement('canvas');
  canvas.width = Math.round(width * scale);
  canvas.height = Math.round(height * scale);
  const context = canvas.getContext('2d', { willReadFrequently: true });
  context.fillStyle = appearance.night ? '#251e19' : '#f6efe2';
  context.fillRect(0, 0, canvas.width, canvas.height);
  context.scale(scale, scale);
  context.drawImage(image, 0, 0);
  return canvas.toDataURL('image/jpeg', 0.85);
}

// The number of visible characters, white space left out, before [range]
// and in the whole section.
function charactersAt(range) {
  const document = range.startContainer.ownerDocument;
  const body = document.body || document.getElementsByTagName('body')[0];
  const total = body ? visibleLength(body.textContent) : 0;
  if (!total || !body.contains(range.startContainer)) return { before: 0, total };
  const before = range.cloneRange();
  before.selectNodeContents(body);
  before.setEnd(range.startContainer, range.startOffset);
  return { before: visibleLength(before.toString()), total };
}

// Draws the page that holds the place [progress] of the way through the text
// of spine section [index], as an image [width] pixels wide. It
// reports the page as `image`, the text progress through the section of the
// page's first and last visible places as `start` and `end`, and the places
// where the `previous` and `next` pages start, or null at the book's ends.
export function previewPage(index, progress, width) {
  const job = previewJob.catch(() => {}).then(async () => {
    const section = Number.isInteger(index) && book.spine.get(index);
    if (!section || typeof progress !== 'number' || !(progress >= 0 && progress <= 1) ||
        typeof width !== 'number' || !(width > 0 && width <= 4096)) throw Error('The destination is not in this book');
    const view = previewRendition();
    await section.load(book.load.bind(book));
    await view.display(placeAt(section, progress));
    const location = view.currentLocation();
    const image = await drawPage(view, width / view.manager.container.clientWidth);
    const first = charactersAt(await book.getRange(location.start.cfi));
    const last = charactersAt(await book.getRange(location.end.cfi));
    const count = book.spine.spineItems.length;
    const total = first.total;
    // A place sits inside its character, so rounding cannot move it to the
    // character's neighbor.
    const place = character => (character + 0.5) / total;
    const firstPage = !total || location.start.displayed.page <= 1;
    const lastPage = !total || location.end.displayed.page >= location.end.displayed.total;
    return {
      image,
      part: index,
      start: total ? first.before / total : 0,
      end: total && !lastPage ? Math.min(1, last.before / total) : 1,
      previous: !firstPage ? { part: index, progress: place(first.before - 1) } :
        index > 0 ? { part: index - 1, progress: 1 } : null,
      next: !lastPage ? { part: index, progress: place(Math.min(total - 1, last.before + 1)) } :
        index + 1 < count ? { part: index + 1, progress: 0 } : null,
    };
  });
  previewJob = job;
  return job;
}
