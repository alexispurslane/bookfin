---
id: boo-ju83
status: open
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

