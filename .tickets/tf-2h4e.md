---
id: tf-2h4e
status: open
deps: [tc-rap6]
links: []
created: 2026-11-09T12:21:40Z
type: chore
priority: 3
assignee: Alexis Purslane
parent: boo-b2ey
---
# Delete epub.js's word-start rule after the Chromium comparison is gone

Since t1-7l9c, a page saves its first visible character (firstVisible in lib/reader/epub/places.dart). wordStart, epub.js's word-start rule, stays in places.dart only because test/reader/epub/trial/fidelity_test.dart (the Chromium comparison) calls it. tc-rap6 deletes test/reader/epub/trial/. After that merges, delete wordStart, its group "epub.js's word start, for the comparison with Chromium" in test/reader/epub/places_test.dart, and the sentence about it in docs/plans/native-epub-reader.md ("The saved start of a page").

## Acceptance Criteria

grep finds no wordStart in lib/, test/ or tool/. flutter analyze lib test is clean and the full flutter test passes.

