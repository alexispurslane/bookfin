---
id: t5-ynlj
status: closed
deps: []
links: []
created: 2026-11-08T22:14:17Z
type: bug
priority: 2
assignee: Alexis Purslane
parent: boo-b2ey
---
# Rank the user agent sheet below book style sheets in the cascade

The native cascade (Cascade.compute in lib/reader/epub/css.dart) ranks every normal rule by specificity, whatever its origin. So a user agent rule with a higher specificity beats a book's own rule. Example: the user agent rule `section h1 { font-size: 1.5em; margin: .83em 0 }` beats the showcase book's `h1 { font-size: 1.4em; margin: 1.5em 0 1em }`, and Chromium does the opposite (CSS Cascade 4: origin comes before specificity). Found in tc-n6wv: with exact line positions, the showcase book salt at 23 pixels fit one more line on its first page than epub.js did, because its heading was 34.5 pixels instead of 32.2.

