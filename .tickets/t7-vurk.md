---
id: t7-vurk
status: open
deps: []
links: []
created: 2026-11-09T20:42:57Z
type: bug
priority: 3
assignee: Alexis Purslane
parent: boo-b2ey
---
# Make the hyphenated paragraph step budget test pass under heavy load

Found in t5-4l4d. With BOOKFIN_EPUB_STEPS=1, step_budget_test.dart 'the layout step of a long hyphenated paragraph takes a few times one layout of it' failed in 2 of 4 runs while the Mac's load was 20 to 25 on 10 cores, and passed in the other 2. It compares two host timings (hyphenated < plain * 4) and touches only layout.dart. One passing run printed 24.1 ms with hyphens against 16.9 ms without at 20 px.

## Acceptance Criteria

The test passes in 10 runs in a row at a load above 20 on 10 cores, or it measures something that load does not change.

