---
id: boo-9zgy
status: closed
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

**2026-11-13T03:09:08Z**

Orchestrator integration verified on main with source changes through 11266d7e. nix develop --command flutter test --no-pub --concurrency=4 --reporter expanded: 3114 passed, 25 skipped, 0 failed in 3m23s, exit 0. Log: /tmp/bookfin-astra-full-suite-fixed.log. The earlier full run exposed boo-9zgy; its deterministic test fix is integrated. No new device acceptance or coverage/mutation campaign is claimed. Integrated and closed by the orchestrator.
