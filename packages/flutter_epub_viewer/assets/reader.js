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
    resolveDestination: () => resolveDestination,
    search: () => search,
    searchBook: () => searchBook,
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
  async function visibleLocation(book2, cfi, resource) {
    const collapsed = new window.ePub.CFI(cfi);
    collapsed.collapse(true);
    const start = collapsed.toString();
    const section = book2.spine.get(collapsed.spinePos);
    if (!section || resourceFor(book2, section) !== resource) throw Error("Location resource does not match");
    const range = await book2.getRange(start);
    if (!range) throw Error("Location cannot be resolved");
    return { cfi: start, resource, quote: quoteAt(range) };
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
  var book;
  var rendition;
  var settings;
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
    rendition = book.renderTo("viewer", {
      width: "100%",
      height: "100%",
      spread: "none",
      flow: "paginated",
      allowScriptedContent: false,
      allowPopups: false,
      method: "write"
    });
    rendition.hooks.content.register((contents) => {
      const document2 = contents.document;
      const style = document2.createElement("style");
      style.textContent = '@font-face{font-family:BookfinSerif;src:url("https://bookfin-runtime.invalid/SourceSerif4.ttf")}body{overflow-wrap:break-word;line-height:1.65!important;padding:0 18px!important}img{max-width:100%!important;height:auto}a:focus{outline:2px solid currentColor}';
      document2.head.appendChild(style);
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
        const start = await visibleLocation(book, location.start.cfi, resourceFor(book, section));
        if (sequence === locationEvent) send("readerLocation", start);
      } catch (_) {
        send("readerFailure", "The visible reading place could not be saved. Use Contents to continue.");
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
    const current = rendition.location && rendition.location.start.cfi;
    applyAppearance(rendition, fontSize, night);
    if (restore && current) await withNavigation(() => rendition.display(current));
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
  return __toCommonJS(reader_exports);
})();
