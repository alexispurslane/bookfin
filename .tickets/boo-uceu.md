---
id: boo-uceu
status: in_progress
deps: [t9-cx1u]
links: []
created: 2026-11-07T23:17:21Z
type: task
priority: 3
assignee: Alexis Purslane
parent: boo-bquq
tags: [test]
---
# Make invariant checks inside listeners fail their tests

From tc-y4ij. A ChangeNotifier reports an exception thrown by a listener through FlutterError instead of failing the test, so a checkInvariants() call inside addListener never fails its test. tc-y4ij fixed this in test/catalog/catalog_signals_test.dart by collecting each StateError and expecting none. Other test files call checkInvariants from listeners: test/app/app_shell_test.dart, test/playback/signals_test.dart, test/downloads/retained_test.dart, test/downloads/status_test.dart, test/downloads/transfer_test.dart (check each). Add one shared test helper that watches a source and fails on any invariant error, and use it everywhere. Owned files: the named test files and a new helper under test/.

## Acceptance Criteria

Removing a protection that an invariant guards makes each of these tests fail, not just log.


## Notes

**2026-11-08T00:12:38Z**

Orchestrator, Nov 7: one agent does tc-qdk7, t9-cx1u and boo-uceu together (group A), to save agent cycles on playback.dart and the broad notifications.

**2026-11-08T01:04:06Z**

Group A agent, Nov 7: a search of test/ found one test that checks invariants from a listener: test/catalog/catalog_signals_test.dart. The named candidates (app_shell_test, playback/signals_test, downloads/retained_test, status_test, transfer_test) call checkInvariants only after an await, never inside a listener. app_shell_test only stubs checkInvariants. The new helper test/invariant_watch.dart (expectInvariantsAtEveryNotice) replaces the try/catch in the catalog test. Proof: without the verification reset in CatalogController._begin and _failure, the test fails with 'An invariant failed at a notice.' Playback invariants hold only when no command is in flight, so a check at every Playback notice would need a design change first.
