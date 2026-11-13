---
id: boo-9zgy
status: in_progress
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


## Notes

**2026-11-13T03:05:03Z**

Reproduced on main at 0643cebc during the full Nix Flutter suite: 3113 passed, 25 skipped, 1 failed. The failure expected [turn, previous] but got [previous, turn]. The test depended on 500 long paragraphs finishing later than a short next section in separate isolates, which is not a scheduling guarantee. Reused HeldPrepares to withhold the previous section until the next-section turn completes. The test now proves that the turn can complete while the previous section is pending, then releases and observes that section. Teardown releases it even after an assertion failure. Reduced the previous fixture to four paragraphs because its size no longer controls synchronization. Nix Flutter test of test/reader/epub/page_source_test.dart: 27 passed, 1 benchmark skipped. Full-suite rerun follows.
