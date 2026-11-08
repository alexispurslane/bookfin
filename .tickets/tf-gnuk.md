---
id: tf-gnuk
status: open
deps: []
links: []
created: 2026-11-08T16:27:49Z
type: feature
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
tags: [platform, macos, ios, reader]
---
# Read EPUB books in the Apple WebKit reader on macOS and iOS

On Android the EPUB viewport serves its runtime and the book from two private https origins through shouldInterceptRequest, with a status, a Content-Security-Policy and CORS headers on every reply. WKWebView cannot intercept https. flutter_inappwebview_macos 1.2.0-beta.3 serves custom schemes, but its CustomSchemeHandler replies with a plain URLResponse, so a reply has no HTTP status and no headers: the reader loses its CSP and its cross-origin rules. So the macOS app shows the existing 'EPUB reading is available in the Android app' message. Found in boo-gnx9; see docs/plans/platforms.md.

Design A: keep two private origins on a custom scheme (bookfin://runtime.invalid, bookfin://publication.invalid), and patch the plugin's CustomSchemeHandler to reply with HTTPURLResponse (status and headers). Cost: a vendored patch of flutter_inappwebview_macos and _ios, and a scheme switch in ReaderResources, Publication and reader.js. Android keeps its path.
Design B: serve the runtime and the book from two loopback HTTP servers in the app (127.0.0.1, two ports, an unguessable path token), with full headers, on every platform that lacks request interception. Cost: a local listener that other local processes can reach, an App Transport Security exception for loopback, and a second serving path beside Android's.

## Acceptance Criteria

The macOS app opens a downloaded EPUB from the fixture, turns pages, and keeps its reading place over a restart; every reply carries the same CSP and CORS rules as on Android.

