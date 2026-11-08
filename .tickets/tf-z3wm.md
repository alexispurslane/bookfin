---
id: tf-z3wm
status: open
deps: []
links: []
created: 2026-11-08T16:40:03Z
type: task
priority: 3
assignee: Alexis Purslane
parent: boo-fs0n
---
# Serve the reader WebView's resource requests without the main thread

Found in boo-duaq (2026-11-08). The EPUB WebView sets useShouldInterceptRequest, so flutter_inappwebview sends every resource request (section XHTML, style sheets, images, the font) from Chromium's IO thread to Android's main thread and the Dart UI isolate, and waits for the bytes there. In Flutter 3.47 that thread also runs the UI isolate. The scrub deck's hidden rendition loads a new section's resources this way. Measure the cost on a book with large images, then serve publication files from a handler that runs off the main thread (for example the plugin's WebViewAssetLoader with a path handler over the verified local files).

