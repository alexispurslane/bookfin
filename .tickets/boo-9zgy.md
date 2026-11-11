---
id: boo-9zgy
status: open
deps: []
links: []
created: 2026-11-11T20:56:42Z
type: bug
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Make the page source section-order test pass under heavy load

test/reader/epub/page_source_test.dart 'the order of work around the shown page a turn into the next section waits only for that section's prepare, not for the previous section's' failed once in a full run with --concurrency=4 at host load 17 to 21 (2026-11-11, main after merging t3/30cd0bb4). It passed 3 of 3 runs alone. Find the timing assumption and make the test wait on the event instead.

