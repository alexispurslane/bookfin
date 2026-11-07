---
id: boo-uceu
status: open
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

