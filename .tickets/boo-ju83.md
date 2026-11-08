---
id: boo-ju83
status: closed
deps: []
links: []
created: 2026-11-08T17:17:15Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
---
# Measure a Flutter-native EPUB renderer against epub.js

User decision (2026-11-08): run a measured trial of an EPUB reader that stays in Flutter (no WebView), with the WebView kept as a fallback for books it cannot render. Why: the WebView reader is slow to draw scrub-deck pages (t6-rt20), stalls Android's main thread (tf-z3wm, t6-6gej), cannot serve its files on Apple WebKit (tf-gnuk), and its plugin is beta on Linux and Windows. The trial changes nothing in the app. It reports fidelity and speed so the user can decide whether to build it. tf-gnuk waits for this result.


## Notes

**2026-11-08T18:36:33Z**

Trial done; report in docs/research/native-epub.md. Body text at 20 px matches epub.js in 26,544 of 26,548 line starts and 1,468 of 1,490 page starts; 313 of 317 sections pass the support check (every failure is a table); every saved place resolves both ways. Host: chapter layout median 6.6 ms, page draw median 0.8 ms, against epub.js 235 ms first show and 103 ms per scrub page. The Pixel 8 run did not happen: another T3 session held the device (DEVICE_IN_USE), so the trial app was uninstalled unrun; the report lists the steps. Retained memory was not measured reliably. Found te-9m1y (the sanitizer empties Standard Ebooks sheets).

**2026-11-08T18:47:22Z**

User decision (2026-11-08): go all in on the Flutter renderer. No Pixel benchmark. The Flutter renderer becomes the only EPUB and MOBI reader on every platform; the WebView reader and epub.js are removed at the end, with no per-book fallback. Saved places stay CFIs.
