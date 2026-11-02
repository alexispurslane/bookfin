# EPUB navigator host probes

This directory is research for `t3-9r9u` and `boo-9wgg`.
It is not a reader implementation or dependency approval.
Read `docs/research/epub-navigator.md` for the recommendation and release gates.

Run from the repository root:

```sh
nix develop ./tool/research/readers#navigator --command bash tool/research/readers/navigator/run
```

The runner downloads exact source archives and checks their SHA-256 hashes.
`sources.json` records those hashes and URLs.
The existing `corpus-manifest.json` supplies public-book hashes and rights records.
The runner downloads only its EPUB and MOBI entries.
It uses no standalone HTML or Markdown books.
XHTML and CSS inside EPUB remain necessary.
The generated semantic EPUB uses original probe text and the existing bundled font with its license.
The generated probe text is dedicated to the public domain under CC0, matching the original reader fixtures.

`package-lock.json` pins the host DOM dependency.
The two `pubspec.lock` files pin the Flutter resource probe and the PDF dependency-solver probe.
The research Nix flake pins the toolchain through its existing lock file.
No toolchain is installed globally.
The runner starts no browser, server, emulator, or Android build.
It runs commands sequentially and records memory and machine load before Flutter tests.

## What runs

| Probe | Operation | Limit |
| --- | --- | --- |
| Python raster fallback | Resolve the real KF8 SVG wrapper to its exact JPEG; reject 14 active, remote, or non-wrapper variants and wrong dimensions | Research-only, deliberately narrow fallback; not a general SVG sanitizer |
| DOM navigation | Run the package's actual bundled JavaScript against nine local EPUB editions; search, resolve contents links, restore CFI text after styling and reopening | DOM means a parsed document tree; no pixels, browser layout, font application, pagination, or screen reader |
| Clean upstream engine | Repeat the DOM tests using the separately pinned epub.js 0.3.93 distribution | Does not establish that the package's different bundled engine is this upstream version |
| Search regressions | First prove the inline-phrase failure; then show why calling the existing multi-node search alone loses other matches; apply bounded research patches and rerun | The patches do not prove every Unicode, whitespace, long fragmented query, or malformed-chapter case |
| Flutter resource tests | Run the actual package ZIP reader and Android-style resource interceptor on the host; paint the PNG and resolved KF8 JPEG | No native WebView or Android interception is exercised |
| PDF solver | Resolve pdfrx 2.11.0 and flutter_epub_viewer 2.2.1 together without EPUBX | No new PDF runtime or APK proof |
| Upstream security gates | Require an explicit remote-request denial and removal of active SVG attributes | Both intentionally fail against the unmodified package |

The runner checks both expected security failures.
A compiler error does not count as their expected result.
It also checks the expected assertion messages for each search regression.
It restores downloaded source files after applying research patches.
The original Python red log is historical evidence from the stub before the fallback implementation.
The runner does not recreate that stub.
The local Git attributes preserve terminal-output whitespace and unified-patch context lines.

## Files and cleanup

The source archives, public books, converted books, and extracted editions are in `.cache/navigator/`.
The generated `books.json` contains local paths and edition fingerprints for the DOM probe.
The two Flutter projects keep generated build files in their ignored project directories.
The committed evidence lives in `tool/research/readers/evidence/navigator/`.
The PNG evidence is painted by a host Flutter test, not captured from Android.
No source or corpus archive is committed.

The runner's source patches affect ignored downloaded sources only.
`search-inline.patch` changes the wrapper's search call.
`search-repeated.patch` changes the bundled engine's occurrence loop and its final search windows.
`upstream-search.patch` makes the same two engine changes in the separately pinned upstream distribution.
The production fork must port these changes to the corresponding source modules and preserve their tests.
No engine rebuild was attempted here.

The caches can be removed without losing evidence:

```sh
rm -rf .cache/navigator tool/research/readers/navigator/node_modules \
  tool/research/readers/navigator/widget/build tool/research/readers/navigator/widget/.dart_tool \
  tool/research/readers/navigator/solver/.dart_tool
```

The runner does not change the shared application, SDK, emulator settings, or any Jellyfin account.
The orchestrator owns package approval, Android acceptance, production integration, and ticket closure.
