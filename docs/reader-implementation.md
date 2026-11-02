# EPUB reader implementation

This is an implementation candidate for `t3-9r9u` and `boo-9wgg`, not Android or release acceptance. The two tickets remain in progress. No device, browser, app installation, production server, or credentials were used for this task.

## Boundaries and ownership

Review correction R1 keeps one canonical XML tree from passive admission through search, location validation, and the iframe. The iframe imports the serialized XML tree rather than passing it through `document.write` and the HTML parser. It therefore does not insert implicit table bodies, move table text, or split paragraph blocks. Source IDs, text, local styles, passive-resource rules, processed bytes, and processed-content identity remain unchanged. Actual iframe-boundary tests reproduce all three prior failures and exercise viewport-to-source saving plus source-to-viewport search and contents destinations. These host tests do not prove Android layout, resource loading, or native sandbox enforcement.

`Publication.admit` is the only owner of publication admission. It reads a bounded ZIP archive and creates new, passive XHTML and CSS resources. No raw chapter or SVG is passed to the viewport. A processed publication has immutable resource bytes, an original-file SHA-256 digest, and a processed-content SHA-256 identity. The processed identity includes the admission-policy version, original digest, paths, media types, and processed bytes. Changing admission rules must change `Publication.policy`.

`ReaderResources` owns request admission for that processed publication and the exact bundled runtime assets. It returns an explicit denial for every unlisted request; it never delegates a request to the network. Trusted runtime and publication resources have separate reserved HTTPS origins and content-security policies. The runtime policy permits admitted local styles, images, and fonts. Publication documents prohibit scripts, connections, forms, frames, and objects. The engine retains its no-script iframe sandbox. Flutter also denies native network loading, unlisted navigation, permissions, geolocation, windows, downloads, file access, content access, storage, and third-party cookies. App-wide network policy and Android manifests are unchanged.

`ReaderSession` owns the current account, source edition, admitted publication, visible reading position, search generation, and reader commands. Asynchronous results carry a session generation; account, credential, source, or book changes invalidate old results. Only a complete file supplied by `Downloads.localFile` can reach the file loader. The production loader rejects non-file URLs and symbolic-link files, checks the archive size, and runs admission outside the UI thread.

Reading positions and bookmarks use the existing `TextPosition`, record identifiers, account keys, and personal-record persistence. `LocalResumeStore.reading` is an adapter for a reading section within the existing account record, not another bookmark database. Serialized record merges retain audio and reading sections. Audio positions are not converted to text positions.

`Publication.checkInvariants()` checks canonical resource paths, matching media types, and a reading order made only of admitted documents. `ReaderSession.checkInvariants()` checks that account records, the current publication, and its reading position belong to the current account and source. These methods run on demand, including in tests; a failed check is a bug, not a recovery path.

## Supported content and bounds

The 16 MiB resource limit and 128 MiB total limit also apply to processed bytes. Short wrapper references cannot expand into an oversized published chapter.

| Input | Admission or behavior |
| --- | --- |
| Archive | At most 64 MiB, 4096 entries, 16 MiB per expanded resource, and 128 MiB total expansion. Stored and deflated entries only; CRC and declared output length must match. Entries larger than 1 MiB must have a compression ratio of at most 250. No encryption, symbolic links, duplicate paths, overlapping entries, absolute paths, or path traversal. |
| XML documents | UTF-8, at most 4 MiB each, 200000 nodes, and depth 128. Entity declarations are rejected. One local OPF package and a nonempty XHTML reading order are required. |
| XHTML | Rebuilt from an explicit tag and attribute allowlist. Headings, local links, language, direction, image descriptions, and accessibility attributes remain. Scripts, event handlers, active objects, media, frames, and unsafe namespaces are removed. |
| CSS | Local stylesheets, local imports, images, and fonts are admitted. Escaped or active CSS and external URL references are blocked with a visible warning. This is deliberately bounded CSS support, not full CSS compatibility. Native request admission remains authoritative for other CSS URL syntax. |
| PNG and JPEG | Decoded independently according to the admitted media type. At most 16 million pixels and one frame. Invalid images become an explicit unsupported-image description. |
| SVG | Never served or executed. Only the researched exact single-local-JPEG wrapper with matching dimensions is replaced by its validated JPEG. Other SVG becomes an explicit unsupported-image description. This is not generic SVG sanitization. |
| Fonts | Local TTF, OTF, WOFF, and WOFF2 signatures and bounded bytes are admitted. Font parsing remains the platform's job. Delivered bytes are not proof of an applied font. |
| Unsupported editions | Fixed-layout metadata, encrypted or obfuscated resources, and non-EPUB files report an error. MOBI conversions are corpus fixtures only. Standalone HTML and Markdown are not supported. |

The reader uses real XHTML/CSS in the bundled EPUB engine, not an extracted-text preview. It provides contents, internal fragment links, page controls, text sizing, cream/sepia and night palettes, search, bookmarks with editable titles and notes, and resume. It keeps the existing audio mini-player. Web and other platforms show an explicit unsupported-reader message without disabling the existing web app.

## Locations and search

A locator stores the visible-start EPUB CFI, meaning the engine's document-and-text position, with a resource path and nearby text. The personal record also binds it to its edition, source key, original source revision, original-file digest, processed identity, admission-policy version, and engine version. Incompatible records remain stored but are not applied. The engine verifies both the resource and nearby text before navigating. Host tests exercise encoded and nested fragments and a fresh engine reopen. They do not prove which character is physically visible on Android.

Search joins body text across inline nodes and retains repeated matches and short documents. It folds whitespace and lowercases text while mapping results back to original UTF-16 text offsets. It excludes explicitly hidden elements and inline hidden styles, but does not evaluate all stylesheet visibility. It does not perform Unicode normalization, accent folding, locale-specific case matching, or full Unicode case folding. These bounds are visible in the search sheet.

Queries are limited to 256 UTF-16 code units. Results are limited to 500 per chapter and 500 per book. Truncation or a failed chapter produces a visible incomplete-search message. Search cancellation and session generations prevent old results from replacing a newer search or another account's results.

## Provenance and reproduction

`packages/flutter_epub_viewer/UPSTREAM.json` pins the selected `flutter_epub_viewer` 2.2.1 source archive and the separately obtained, clean `epubjs` 0.3.93 source archive by SHA-256. The upstream wrapper's different bundled engine is not used. The fork narrows the wrapper API and vendors the clean engine source modules. Changes belong in those modules, not in generated assets.

Two unused or equivalent transitive paths changed during the bounded fork. The unexposed visual-annotation path and its `marks-pane` dependency were removed; Bookfin bookmarks use personal records, not SVG highlights. The `path-webpack` shim was replaced by pinned `path-browserify` 1.0.1. Both original packages declare MIT but omit license text. The replacement has license text. These changes do not select a different EPUB navigator, and both are recorded for parent review.

The npm lockfile pins build and runtime dependencies by integrity. The Nix shell supplies Node.js and Flutter. Bundled assets need no CDN, runtime installation, or network bootstrap. BSD license files and generated dependency license texts are retained and registered with Flutter's license registry. `ASSETS.sha256` records the checked-in runtime assets; rebuilding and verifying them checks reproducibility.

```sh
nix develop --command bash -c 'cd packages/flutter_epub_viewer/engine && npm ci --ignore-scripts --no-audit --no-fund && npm run build && npm run verify && npm test'
nix develop --command flutter test test/reader --reporter expanded
nix develop --command bash tool/bookfin test
nix develop --command flutter analyze
nix develop --command bash tool/bookfin build-android
nix develop --command flutter build web --no-wasm-dry-run
```

The nine-edition corpus is the existing pinned public-domain navigator corpus. If its cache is absent, prepare it with `nix develop ./tool/research/readers#navigator --command bash tool/research/readers/navigator/run`. Then run production admission and the engine tests against the resulting processed bytes:

```sh
nix develop --command flutter test tool/reader/corpus_test.dart --reporter expanded
nix develop --command bash -c 'cd packages/flutter_epub_viewer/engine && node --test test/corpus.cjs'
```

## Acceptance still required

The host tests cover real preprocessing, request replies, actual engine document navigation/search, download verification, account and source isolation, record restart, and production Flutter controls. DOM tests do not render pages and do not enforce Android WebView security. Widget tests use the actual unsupported-platform boundary, not simulated EPUB rendering.

Parent acceptance still needs actual Android XHTML/CSS layout, PNG/JPEG display, applied embedded and fallback fonts, large-text pagination, visible-start resume after force-stop or process death, TalkBack reading order and focus, offline operation, and native request/navigation/permission interception. A failed attempt must not be replaced by inferred device acceptance. Readium remains the documented fallback if a concrete impossibility is established; this implementation does not silently switch navigators or drop required features.

Coverage and mutation testing are intentionally deferred to the parent after user acceptance. Exact commands, test counts, build results, and historical red tests are indexed in `tool/evidence/reader/README.md`.
