---
id: boo-35up
status: open
deps: []
links: []
created: 2026-11-07T21:34:40Z
type: task
priority: 3
assignee: Alexis Purslane
parent: boo-fs0n
tags: [test]
---
# Fix the PDF page draw test that fails under heavy load

test/reader/pdf_navigation_test.dart 'repeated original-page requests share one pending draw and release its image' failed once in a full run at 7fd0936 with load near 25 on 10 cores. It passed 3 of 3 runs alone and in the next full run. Find the timing assumption and make the test deterministic.

## Acceptance Criteria

The test passes in a soak run of the full suite under parallel load.

