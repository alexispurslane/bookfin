var bookfinReader = (() => {
  var __defProp = Object.defineProperty;
  var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
  var __getOwnPropNames = Object.getOwnPropertyNames;
  var __hasOwnProp = Object.prototype.hasOwnProperty;
  var __export = (target, all) => {
    for (var name in all)
      __defProp(target, name, { get: all[name], enumerable: true });
  };
  var __copyProps = (to, from, except, desc) => {
    if (from && typeof from === "object" || typeof from === "function") {
      for (let key of __getOwnPropNames(from))
        if (!__hasOwnProp.call(to, key) && key !== except)
          __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
    }
    return to;
  };
  var __toCommonJS = (mod) => __copyProps(__defProp({}, "__esModule", { value: true }), mod);

  // src/reader.js
  var reader_exports = {};
  __export(reader_exports, {
    applyAppearance: () => applyAppearance,
    cancelSearch: () => cancelSearch,
    configure: () => configure,
    display: () => display,
    go: () => go,
    move: () => move,
    openBook: () => openBook,
    previewPage: () => previewPage,
    resolveDestination: () => resolveDestination,
    search: () => search,
    searchBook: () => searchBook,
    seek: () => seek,
    verifyLocation: () => verifyLocation,
    visibleLocation: () => visibleLocation
  });
  function resourceFor(book2, section) {
    const base = new URL(book2.url.toString());
    const url = new URL(section.url, base);
    if (url.origin !== base.origin || !url.pathname.startsWith(base.pathname)) throw Error("Non-local reading resource");
    return decodeURIComponent(url.pathname.slice(base.pathname.length));
  }
  function quoteAt(range) {
    const document2 = range.startContainer.ownerDocument;
    const body = document2.body || document2.getElementsByTagName("body")[0];
    if (!body || !body.contains(range.startContainer)) return "";
    const after = range.cloneRange();
    after.selectNodeContents(body);
    after.setStart(range.startContainer, range.startOffset);
    return after.toString().slice(0, 120);
  }
  var visibleLength = (text) => text.replace(/\s/g, "").length;
  function progressAt(range) {
    const document2 = range.startContainer.ownerDocument;
    const body = document2.body || document2.getElementsByTagName("body")[0];
    if (!body || !body.contains(range.startContainer)) return 0;
    const total = visibleLength(body.textContent);
    if (!total) return 0;
    const before = range.cloneRange();
    before.selectNodeContents(body);
    before.setEnd(range.startContainer, range.startOffset);
    return Math.round(visibleLength(before.toString()) / total * 1e6) / 1e6;
  }
  function placeAt(section, progress) {
    const document2 = section.document;
    const body = document2.body || document2.getElementsByTagName("body")[0];
    const total = body ? visibleLength(body.textContent) : 0;
    if (!total) return section.href;
    let wanted = Math.min(total - 1, Math.floor(progress * total));
    const walker = document2.createTreeWalker(body, NodeFilter.SHOW_TEXT | NodeFilter.SHOW_CDATA_SECTION);
    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
      const count = visibleLength(node.data);
      if (wanted >= count) {
        wanted -= count;
        continue;
      }
      let offset = 0;
      for (; offset < node.data.length; offset++) if (!/\s/.test(node.data[offset]) && wanted-- === 0) break;
      const range = document2.createRange();
      range.setStart(node, offset);
      range.collapse(true);
      return section.cfiFromRange(range);
    }
    return section.href;
  }
  async function visibleLocation(book2, cfi, resource, displayed) {
    const collapsed = new window.ePub.CFI(cfi);
    collapsed.collapse(true);
    const start = collapsed.toString();
    const section = book2.spine.get(collapsed.spinePos);
    if (!section || resourceFor(book2, section) !== resource) throw Error("Location resource does not match");
    const range = await book2.getRange(start);
    if (!range) throw Error("Location cannot be resolved");
    let chapter = section.document.querySelector("h1, title")?.textContent.trim() || `Chapter ${section.index + 1}`;
    let chapterCfi;
    const comparator = new window.ePub.CFI();
    for (const item of flatten(book2.navigation.toc)) {
      const url = new URL(book2.resolve(item.href));
      if (url.pathname !== new URL(section.url).pathname) continue;
      const target = url.hash ? section.document.getElementById(decodeURIComponent(url.hash.slice(1))) : section.document.body;
      if (!target) continue;
      const candidate = section.cfiFromElement(target);
      if (comparator.compare(candidate, start) <= 0 && (!chapterCfi || comparator.compare(candidate, chapterCfi) >= 0)) {
        chapter = item.title;
        chapterCfi = candidate;
      }
    }
    const pages = displayed && Number.isInteger(displayed.page) && Number.isInteger(displayed.total) && displayed.page > 0 && displayed.total >= displayed.page ? { page: displayed.page, pages: displayed.total } : {};
    const progress = displayed ? { progress: progressAt(range) } : {};
    return { cfi: start, resource, quote: quoteAt(range), chapter: chapter.slice(0, 512), ...pages, ...progress };
  }
  async function verifyLocation(book2, location) {
    const resolved = await visibleLocation(book2, location.cfi, location.resource);
    if (location.quote && !resolved.quote.startsWith(location.quote)) throw Error("Saved quote does not match this document");
    return resolved;
  }
  async function resolveDestination(book2, href, base, packagePath) {
    const url = new URL(href, new URL(packagePath, base));
    const root = new URL(base);
    if (url.origin !== root.origin || !url.pathname.startsWith(root.pathname) || url.search) throw Error("Non-local destination");
    const section = book2.spine.spineItems.find((candidate) => new URL(candidate.url, root).pathname === url.pathname);
    if (!section) throw Error("Destination is not a reading-order document");
    await section.load(book2.load.bind(book2));
    const document2 = section.document;
    const target = url.hash ? document2.getElementById(decodeURIComponent(url.hash.slice(1))) : document2.body || document2.getElementsByTagName("body")[0];
    if (!target) throw Error("Destination fragment does not exist");
    const walker = document2.createTreeWalker(target, 4);
    const firstText = walker.nextNode();
    const range = document2.createRange();
    if (firstText) {
      range.setStart(firstText, 0);
      range.collapse(true);
    }
    return visibleLocation(book2, firstText ? section.cfiFromRange(range) : section.cfiFromElement(target), resourceFor(book2, section));
  }
  async function searchBook(book2, query, isCurrent) {
    if (!query.trim() || query.length > 256) return { hits: [], error: "Enter between 1 and 256 characters." };
    const hits = [];
    let error = null;
    for (const section of book2.spine.spineItems) {
      if (!isCurrent()) return { hits: [], cancelled: true, error: null };
      try {
        await section.load(book2.load.bind(book2));
        if (!isCurrent()) return { hits: [], cancelled: true, error: null };
        const matches = section.find(query);
        if (matches.incomplete) error = "Search is incomplete. Only the first 500 matches per chapter are shown.";
        for (const match of matches) {
          if (hits.length >= 500) return { hits, error: "Search is incomplete. Only the first 500 matches are shown. Use a longer phrase." };
          hits.push({ location: await visibleLocation(book2, match.cfi, resourceFor(book2, section)), excerpt: match.excerpt });
        }
      } catch (_) {
        error = "Search is incomplete. A chapter could not be searched. Retry or use Contents.";
      } finally {
        section.unload();
      }
      await new Promise((resolve) => setTimeout(resolve, 0));
    }
    return { hits, error };
  }
  function addReaderStyle(document2) {
    const style = document2.createElement("style");
    style.textContent = '@font-face{font-family:BookfinSerif;src:url("https://bookfin-runtime.invalid/SourceSerif4.ttf")}body{overflow-wrap:break-word;line-height:1.65!important;padding:0 18px!important}img{max-width:100%!important;height:auto}a:focus{outline:2px solid currentColor}';
    document2.head.appendChild(style);
  }
  var renditionOptions = {
    width: "100%",
    height: "100%",
    spread: "none",
    flow: "paginated",
    allowScriptedContent: false,
    allowPopups: false,
    method: "write"
  };
  var book;
  var rendition;
  var settings;
  var appearance;
  var searchRequest = 0;
  var searchJob = Promise.resolve();
  var navigationJob = Promise.resolve();
  var locationEvent = 0;
  function send(name, value) {
    if (window.flutter_inappwebview) return window.flutter_inappwebview.callHandler(name, value);
  }
  function withNavigation(action) {
    const operation = navigationJob.catch(() => {
    }).then(action);
    navigationJob = operation;
    return operation;
  }
  function localAddress(address) {
    const url = new URL(address, settings.base);
    if (url.origin !== new URL(settings.base).origin || !url.pathname.startsWith(new URL(settings.base).pathname) || url.search || url.username || url.password) throw Error("Resource request was denied");
    return url;
  }
  async function requestLocal(address, type) {
    const url = localAddress(address);
    const response = await fetch(url.href, { credentials: "omit", redirect: "error", cache: "no-store" });
    if (!response.ok) throw Error("Local resource is unavailable");
    if (type === "binary") return response.arrayBuffer();
    if (type === "blob") return response.blob();
    const text = await response.text();
    if (type === "json") return JSON.parse(text);
    if (/\.(?:xml|opf|ncx|xhtml|html|htm)$/i.test(url.pathname) || ["xml", "xhtml", "html", "opf", "ncx"].includes(type)) {
      const document2 = new DOMParser().parseFromString(text, "application/xhtml+xml");
      if (document2.getElementsByTagName("parsererror").length) throw Error("Local document cannot be parsed");
      return document2;
    }
    return text;
  }
  function flatten(items, depth = 0) {
    return items.flatMap((item) => [
      { title: item.label.trim() || "Untitled chapter", href: item.href, depth },
      ...flatten(item.subitems || [], Math.min(depth + 1, 16))
    ]);
  }
  async function openBook(configuration) {
    settings = configuration;
    book = window.ePub(void 0, { requestMethod: requestLocal, replacements: "none" });
    await book.open(settings.base, "directory");
    await book.ready;
    rendition = book.renderTo("viewer", renditionOptions);
    rendition.hooks.content.register((contents) => {
      const document2 = contents.document;
      addReaderStyle(document2);
      document2.addEventListener("click", (event) => {
        const link = event.target.closest && event.target.closest("a[href]");
        if (link) {
          event.preventDefault();
          event.stopImmediatePropagation();
          let href;
          try {
            href = new URL(link.getAttribute("href"), document2.querySelector("base").href).href;
          } catch (_) {
            return;
          }
          go(href).catch(() => send("readerWarning", "This internal link could not be opened. Use Contents to continue."));
        } else if (!contents.window.getSelection().toString()) {
          send("readerTap", null);
        }
      }, true);
      let touch;
      document2.addEventListener("touchstart", (event) => {
        if (event.touches.length === 1) touch = { x: event.touches[0].clientX, y: event.touches[0].clientY };
      }, { passive: true });
      document2.addEventListener("touchend", (event) => {
        if (!touch || !event.changedTouches.length || contents.window.getSelection().toString()) return;
        const delta = event.changedTouches[0].clientX - touch.x;
        const vertical = event.changedTouches[0].clientY - touch.y;
        touch = null;
        if (Math.abs(delta) > 60 && Math.abs(vertical) < 50) move(delta < 0).catch(() => send("readerFailure", "The next page could not be opened."));
      }, { passive: true });
    });
    rendition.on("relocated", async (location) => {
      const sequence = ++locationEvent;
      try {
        const cfi = new window.ePub.CFI(location.start.cfi);
        const section = book.spine.get(cfi.spinePos);
        const start = await visibleLocation(book, location.start.cfi, resourceFor(book, section), location.start.displayed);
        if (sequence === locationEvent) send("readerLocation", start);
      } catch (_) {
        if (sequence === locationEvent) send("readerFailure", "The visible reading place could not be saved. Use Contents to continue.");
      }
    });
    rendition.on("displayerror", () => send("readerFailure", "This chapter could not be displayed. Use Contents or retry the download."));
    await configure(settings.fontSize, settings.night, false);
    let initial;
    if (settings.initial) {
      try {
        initial = await verifyLocation(book, settings.initial);
      } catch (_) {
        send("readerWarning", "The saved place does not match this text. Reading starts at the beginning.");
      }
    }
    await rendition.display(initial ? initial.cfi : void 0);
    let entries = flatten(book.navigation.toc);
    if (!entries.length) entries = book.spine.spineItems.filter((section) => section.linear).map((section, index) => ({ title: `Chapter ${index + 1}`, href: section.href, depth: 0 }));
    return entries;
  }
  function move(forward) {
    return withNavigation(() => forward ? rendition.next() : rendition.prev());
  }
  function display(location) {
    return withNavigation(async () => {
      const verified = await verifyLocation(book, location);
      await rendition.display(verified.cfi);
    });
  }
  function seek(index, progress) {
    return withNavigation(async () => {
      const section = Number.isInteger(index) && book.spine.get(index);
      if (!section || typeof progress !== "number" || !(progress >= 0 && progress <= 1)) throw Error("The destination is not in this book");
      await section.load(book.load.bind(book));
      await rendition.display(placeAt(section, progress));
    });
  }
  function go(href) {
    return withNavigation(async () => {
      const location = await resolveDestination(book, href, settings.base, settings.packagePath);
      await rendition.display(location.cfi);
    });
  }
  function applyAppearance(viewport, fontSize, night) {
    const paper = night ? "#251e19" : "#f6efe2";
    const ink = night ? "#dcc9a9" : "#39291f";
    document.body.style.backgroundColor = paper;
    viewport.themes.default({
      html: { "font-family": 'BookfinSerif, "Source Serif 4", serif' },
      body: { background: `${paper}!important`, color: `${ink}!important` },
      a: { color: `${ink}!important` }
    });
    viewport.themes.fontSize(`${Math.max(14, Math.min(fontSize, 96))}px`);
  }
  async function configure(fontSize, night, restore = true) {
    const update = async () => {
      const current = rendition.location && rendition.location.start.cfi;
      appearance = { fontSize, night };
      applyAppearance(rendition, fontSize, night);
      if (preview) applyAppearance(preview, fontSize, night);
      if (restore && current) await rendition.display(current);
    };
    return restore ? withNavigation(update) : update();
  }
  function search(query, request) {
    searchRequest = request;
    const operation = searchJob.catch(() => {
    }).then(() => searchBook(book, query, () => searchRequest === request));
    searchJob = operation;
    return operation;
  }
  function cancelSearch(request) {
    if (searchRequest === request) searchRequest = -1;
  }
  var preview;
  var previewJob = Promise.resolve();
  var inlined = /* @__PURE__ */ new Map();
  function previewRendition() {
    if (preview) return preview;
    const viewer = document.getElementById("viewer");
    if (getComputedStyle(viewer).position === "static") viewer.style.position = "relative";
    const box = document.createElement("div");
    box.inert = true;
    box.setAttribute("aria-hidden", "true");
    box.style.cssText = "position:absolute;left:0;top:0;width:100%;height:100%;opacity:0;z-index:-1;pointer-events:none";
    viewer.appendChild(box);
    preview = book.renderTo(box, renditionOptions);
    preview.hooks.content.register((contents) => addReaderStyle(contents.document));
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
  function inline(address) {
    if (!inlined.has(address)) {
      const url = new URL(address);
      const job = url.origin === "https://bookfin-runtime.invalid" && url.pathname === "/SourceSerif4.ttf" ? fetch(url.href, { credentials: "omit", redirect: "error" }).then((response) => response.blob()) : requestLocal(url.href, "blob");
      inlined.set(address, job.then(dataUrl).catch(() => ""));
    }
    return inlined.get(address);
  }
  var inlinedCss = /* @__PURE__ */ new Map();
  function inlineCss(css, base) {
    const key = base + "\n" + css;
    if (!inlinedCss.has(key)) inlinedCss.set(key, inlineCssOnce(css, base));
    return inlinedCss.get(key);
  }
  async function inlineCssOnce(css, base) {
    const pattern = /url\(\s*(['"]?)([^'")]+)\1\s*\)/g;
    const addresses = /* @__PURE__ */ new Set();
    for (const [, , address] of css.matchAll(pattern)) {
      if (!address.startsWith("data:")) addresses.add(new URL(address, base).href);
    }
    const found = new Map(await Promise.all([...addresses].map(async (address) => [address, await inline(address)])));
    return css.replace(pattern, (whole, quote, address) => address.startsWith("data:") ? whole : `url("${found.get(new URL(address, base).href) || ""}")`);
  }
  async function documentCss(document2) {
    const parts = await Promise.all([...document2.querySelectorAll('style, link[rel~="stylesheet"]')].map(async (node) => {
      if (node.localName === "style") {
        const rules = node.sheet ? [...node.sheet.cssRules].map((rule) => rule.cssText).join("\n") : node.textContent;
        return inlineCss(rules, document2.baseURI);
      }
      const address = new URL(node.getAttribute("href"), document2.baseURI).href;
      if (!linkedCss.has(address)) {
        linkedCss.set(address, requestLocal(address, "text").then((css) => inlineCss(css, address), () => ""));
      }
      return linkedCss.get(address);
    }));
    return parts.join("\n");
  }
  var linkedCss = /* @__PURE__ */ new Map();
  var encodedCss = /* @__PURE__ */ new Map();
  async function drawPage(view, scale) {
    const manager = view.manager;
    const frame = manager.views.first();
    const document2 = frame.contents.document;
    const width = manager.container.clientWidth;
    const height = manager.container.clientHeight;
    const left = manager.container.scrollLeft - frame.element.offsetLeft;
    const css = await documentCss(document2);
    if (!encodedCss.has(css)) encodedCss.set(css, encodeURIComponent(css));
    const clone = document2.documentElement.cloneNode(true);
    for (const node of clone.querySelectorAll("style, link, script")) node.remove();
    for (const element of [clone, clone.querySelector("body")]) element?.style.setProperty("overflow", "visible", "important");
    await Promise.all([...clone.querySelectorAll("img[src], image")].map(async (image2) => {
      const attribute = image2.localName === "img" ? "src" : image2.hasAttribute("href") ? "href" : "xlink:href";
      const value = image2.getAttribute(attribute);
      if (value && !value.startsWith("data:")) image2.setAttribute(attribute, await inline(new URL(value, document2.baseURI).href));
    }));
    const marker = "bookfin-preview-style";
    const style = document2.createElementNS("http://www.w3.org/1999/xhtml", "style");
    style.textContent = marker;
    (clone.querySelector("head") || clone).prepend(style);
    const [before, after] = new XMLSerializer().serializeToString(clone).split(marker);
    const frameWidth = frame.element.offsetWidth;
    const head = `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}"><foreignObject x="${-left}" y="0" width="${frameWidth}" height="${height}">`;
    const image = new Image();
    image.src = "data:image/svg+xml;charset=utf-8," + encodeURIComponent(head + before) + encodedCss.get(css) + encodeURIComponent(after + "</foreignObject></svg>");
    await image.decode();
    const canvas = window.document.createElement("canvas");
    canvas.width = Math.round(width * scale);
    canvas.height = Math.round(height * scale);
    const context = canvas.getContext("2d", { willReadFrequently: true });
    context.fillStyle = appearance.night ? "#251e19" : "#f6efe2";
    context.fillRect(0, 0, canvas.width, canvas.height);
    context.scale(scale, scale);
    context.drawImage(image, 0, 0);
    return canvas.toDataURL("image/jpeg", 0.85);
  }
  function charactersAt(range) {
    const document2 = range.startContainer.ownerDocument;
    const body = document2.body || document2.getElementsByTagName("body")[0];
    const total = body ? visibleLength(body.textContent) : 0;
    if (!total || !body.contains(range.startContainer)) return { before: 0, total };
    const before = range.cloneRange();
    before.selectNodeContents(body);
    before.setEnd(range.startContainer, range.startOffset);
    return { before: visibleLength(before.toString()), total };
  }
  function previewPage(index, progress, width) {
    const job = previewJob.catch(() => {
    }).then(async () => {
      const section = Number.isInteger(index) && book.spine.get(index);
      if (!section || typeof progress !== "number" || !(progress >= 0 && progress <= 1) || typeof width !== "number" || !(width > 0 && width <= 4096)) throw Error("The destination is not in this book");
      const view = previewRendition();
      await section.load(book.load.bind(book));
      await view.display(placeAt(section, progress));
      const location = view.currentLocation();
      const image = await drawPage(view, width / view.manager.container.clientWidth);
      const first = charactersAt(await book.getRange(location.start.cfi));
      const last = charactersAt(await book.getRange(location.end.cfi));
      const count = book.spine.spineItems.length;
      const total = first.total;
      const place = (character) => (character + 0.5) / total;
      const firstPage = !total || location.start.displayed.page <= 1;
      const lastPage = !total || location.end.displayed.page >= location.end.displayed.total;
      return {
        image,
        part: index,
        start: total ? first.before / total : 0,
        end: total && !lastPage ? Math.min(1, last.before / total) : 1,
        previous: !firstPage ? { part: index, progress: place(first.before - 1) } : index > 0 ? { part: index - 1, progress: 1 } : null,
        next: !lastPage ? { part: index, progress: place(Math.min(total - 1, last.before + 1)) } : index + 1 < count ? { part: index + 1, progress: 0 } : null
      };
    });
    previewJob = job;
    return job;
  }
  return __toCommonJS(reader_exports);
})();
