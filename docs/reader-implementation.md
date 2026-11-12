# EPUB reader implementation

Bookfin reads EPUB and MOBI books in a Flutter-native renderer in `lib/reader/epub/`. It draws the pages itself, with no WebView, on every platform. `docs/plans/native-epub-reader.md` is its design: modules, owners, layout off the frame path, places and testing. `docs/plans/platforms.md` lists where each format opens.

Until ticket tc-rap6, Bookfin read EPUB books in an Android WebView with a fork of epub.js 0.3.93. That reader and its engine are gone. Git history holds them. The research documents in `docs/research/` and the evidence in `tool/evidence/reader/` keep their record.

## Boundaries and ownership

`Publication.admit` in `lib/reader/epub/publication.dart` is the only owner of publication admission. It reads a bounded ZIP archive and makes new, passive XHTML and CSS resources. No raw chapter or SVG reaches the renderer. An admitted publication has immutable resource bytes, an original-file SHA-256 digest, and a processed-content SHA-256 identity. The identity covers the admission-policy version, the original digest, the paths, the media types and the processed bytes.

Admission output stays byte for byte the same, because the identity is part of every saved place. If admission output changes, every saved place of a book stops matching. A change to the admission rules must change `Publication.policy`. What the renderer needs beyond the admitted files sits beside them, outside the identity: the book's own style sheet texts (`Publication.bookStyles`), image sizes, the contents and the language.

`ReaderSession` owns the current account, the source edition, the admitted publication, the saved reading position, the search generation and the reader commands. Asynchronous results carry a session generation. A change of account, credential, source or book makes old results void. Only a complete file from `Downloads.localFile` reaches the file loader. The loader refuses URLs that are not files and symbolic-link files, checks the archive size, and runs admission outside the UI isolate.

`EpubPager` owns the shown place and the shown page. It reports each new place to the session once, through `onPlace`. `PageSource` owns the prepared sections, the layout runs, the laid pages and the decoded images of one open book. `EpubViewport` draws the shown page and reports gestures. The design document lists every owner.

Reading positions and bookmarks use the existing `TextPosition`, record identifiers, account keys and personal-record persistence. `LocalResumeStore.reading` is an adapter for a reading section in the account record, not a second bookmark database. Record merges keep both the audio and the reading sections. Audio positions do not convert to text positions.

The session keeps the newest unsaved reading snapshot of each account until that snapshot is written. A new save, an account binding, `flush` and disposal retry pending snapshots through the same adapter and merge queue. Only `Exception` failures are recoverable in this write path. Contract failures are errors and propagate. Malformed reading records fail with `FormatException`, so damaged input does not overwrite the damaged record.

`Publication.checkInvariants()` checks canonical resource paths, matching media types, and a reading order of admitted documents only. `ReaderSession.checkInvariants()` checks that the account records, the publication and the reading position belong to the current account and source. These methods run on demand, for example in tests. A failed check is a bug, not a recovery path.

`ReaderSession.setFontSize` stores only the requested text size, from 14 to 40 logical pixels before the system text scale. The viewport presents the scaled size and the theme to the pager as page settings. A settings change keeps the shown place and saves nothing.

## Supported content and bounds

The 16 MiB resource limit and the 128 MiB total limit also apply to processed bytes. A short wrapper reference cannot expand into an oversized chapter.

| Input | Admission or behavior |
| --- | --- |
| Archive | At most 64 MiB, 4096 entries, 16 MiB per expanded resource, and 128 MiB total expansion. Stored and deflated entries only. The CRC and the declared output length must match. Entries larger than 1 MiB must have a compression ratio of at most 250. No encryption, symbolic links, duplicate paths, overlapping entries, absolute paths or path traversal. |
| XML documents | UTF-8, at most 4 MiB each, 200000 nodes, and depth 128. Entity declarations are refused. One local OPF package and a reading order of XHTML documents are required. |
| XHTML | Rebuilt from an explicit list of allowed tags and attributes. Headings, local links, language, direction, image descriptions and accessibility attributes stay. Scripts, event handlers, active objects, media, frames and unsafe namespaces are removed. |
| CSS | The native CSS parser reads the book's style sheets in a worker isolate. It resolves `url()` and `@import` only to files in the publication and loads nothing else. It limits the rules, the selector length and the nesting depth of each sheet. Unknown properties and values are left out. |
| PNG and JPEG | Decoded according to the admitted media type. At most 16 million pixels and one frame. An image that does not decode becomes an explicit unsupported-image description. |
| SVG | Never drawn as SVG. Only an exact wrapper of one local JPEG with matching dimensions is replaced by its JPEG. Other SVG becomes an unsupported-image description, which the renderer draws as text. |
| Fonts | Local TTF, OTF, WOFF and WOFF2 files are admitted. The renderer registers TTF, OTF and WOFF 1 faces. A WOFF 2 face, or a face that does not load, draws in the reader font. |
| Unsupported editions | Fixed-layout metadata, encrypted or obfuscated resources, and files that are not EPUB report an error. A MOBI or AZW3 book converts to an EPUB with libmobi first. |

The renderer lays out real XHTML and CSS: block layout, tables, images and hyphenation. It draws all text in the reader font or in monospace, never in a font of the book. It provides contents, internal links, page turns, text sizes, and cream and night themes. It also provides search, bookmarks with titles and notes, resume, screen reader semantics and text selection. "What stays unsupported" in the design document lists what it approximates.

## Locations and search

A saved place keeps the JSON form that the WebView reader wrote. It holds the EPUB CFI of the first visible word and the resource path. It also holds the first 120 characters of text from the place on and the text progress through the section. The CFI follows epub.js's dialect, so the `engine` value `epubjs-0.3.93-bookfin.1` stays. The personal record also binds the place to its edition, source key, original source revision, original-file digest, processed identity, admission-policy version and engine value. A record that does not match stays stored but does not apply. Before it opens a place, the reader makes sure that the text at the place starts with the saved quote.

The committed fixtures in `test/reader/epub/fixtures/` hold the places that epub.js saved and the line and page starts that Chromium measured. `saved_places_test.dart`, `places_test.dart`, `session_native_test.dart` and `fidelity_test.dart` read them, so places that the WebView reader saved keep opening on the right page.

Search joins body text across inline nodes and keeps repeated matches. It folds white space and lowercases text, and it maps results back to the original UTF-16 offsets. It leaves out hidden elements. It does not normalize Unicode, fold accents, match case by locale or fold case fully. Queries hold at most 256 UTF-16 code units. Results stop at 500 per section and 500 per book. Truncation or a failed section shows a visible incomplete-search message. Cancellation and session generations stop old results from replacing a newer search or another account's results.

## Reproduction

Run these commands from the repository root:

```sh
nix develop --command flutter test test/reader --reporter expanded
nix develop --command bash tool/bookfin test
nix develop --command flutter analyze
nix develop --command bash tool/bookfin build-android
```

`tool/reader/fetch_epub_corpus.py` downloads the public-domain corpus of `tool/reader/epub_corpus.json` into `.cache/epub-corpus/`. Then this command runs the renderer over every book:

```sh
BOOKFIN_EPUB_CORPUS=1 nix develop --command flutter test test/reader/epub/corpus_test.dart
```

`docs/research/native-epub-corpus.md` and `docs/research/native-epub-fidelity.md` record the corpus and fidelity results.
