---
id: boo-x1zf
status: closed
deps: []
links: [boo-23ji, td-1vfz, td-w0wc, t5-6lnm]
created: 2026-11-12T23:41:00Z
type: bug
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Stop a failed command from poisoning the playback command queue

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: mechanism confirmed, trigger for a non-Exception Error plausible. `_enqueue` (lib/playback/playback.dart:891-904) chains each command on `_operations` and handles only Exception and ArgumentError. (a) Any Exception from any command calls `_audioFailed`, so a store failure inside `refreshPersonalRecords` during a background sync pauses the audio and tells the user to download the file again. (b) Any other Error (TypeError, StateError, RangeError) leaves `_operations` as a failed future. Every later command, `flush()` and `close()` then fail at once until the app is killed. Never let a rejected future become the head of the queue. Classify failures for each command: an engine failure goes to `_audioFailed`, and a store failure goes to the save or refresh status. Make the status a closed set of conditions, not one text slot that code compares by string (playback.dart:906-920). The reader has the same queue shape in `_closing` (lib/reader/session.dart:663), so one shared serial queue helper serves both.


## Notes

**2026-11-13T01:43:34Z**

What changed. In lib/playback/playback.dart, _enqueue is now only the queue. It gives each command its own future through a Completer. That future completes as the command completed, and the queue head never fails, so a failed command never stops a later one. An Error that is not an Exception goes to the caller, or to the zone when nothing listens. Nothing turns it into a message. Each command states its kind of failure by how it is queued. An audio command uses the new _audioCommand, where an Exception is an engine failure and calls _audioFailed as before. A records command (addBookmark, editBookmark, deleteBookmark, deleteHistory, refreshPersonalRecords, setJumps, setSleep) uses _enqueue, where an Exception goes to the caller and the audio plays on. A failed save stays the save status of _persistChanges. For refreshPersonalRecords the caller is RecordSync, which already handles the same failure from the reader: a background sync ends as RecordSyncFailure.other, and the stale domain is refreshed at the next sync. In lib/sync/coordinator.dart, recoverKept now also reports nothing when a refresh fails. The _message slot did not change. lib/reader did not change. No shared queue helper was added.

Verification, through nix develop. New file test/playback/command_queue_test.dart, 9 tests. Before the fix 8 failed and 1 passed (the guard "an audio command whose engine call fails stops the audio and says that the file cannot play"). After the fix all 9 pass. With only a queue head that ignores every error, "a bug in a command that nothing awaits is reported once" still failed with an empty list, so the Completer is necessary. The guard test fails when seekEdition is queued as a records command. New group in test/sync/refresh_after_sync_test.dart, 4 tests. Against the old Playback 3 failed (the sync ended with no failure, and the audio stopped twice). With the Playback fix and the old recoverKept the 2 kept-copies tests failed with "Exception: read failed". After both fixes all 4 pass. flutter test test/playback test/sync: 654 passed, 2 skipped (both ask for a pinned shell tool), 0 failed. dart analyze on the 4 changed Dart files: no issues.

Behavior to know. A failed argument guard (ArgumentError) whose caller drops the future is now reported to the zone. Before, the queue head ignored it.

New tickets: td-1vfz (the _writes chain has the same poison defect for an Error from store.save) and td-w0wc (RecordSync names the wrong cause for some failed refreshes).

**2026-11-13T02:10:44Z**

Second change, after the review of the first one. What changed. (1) lib/foundation/serial_queue.dart is new. SerialQueue runs work one piece at a time. Each run has its own future, which carries the value or the failure of that work, and the queue itself never fails. Its idle future completes when every run queued so far has ended. (2) In lib/playback/playback.dart the command queue _operations and the write chain _writes are each a SerialQueue. The Completer left _enqueue for the helper. (3) The name _enqueue is gone. The queue primitive is _inCommandOrder, which no command calls. A command uses _audioCommand, where an Exception is an engine failure, or the new _recordsCommand, where an Exception goes to the caller. An error of the sample stream has its own path, _sampleStreamFailed, because it is itself the handling of an engine failure. (4) A save that fails with an Error no longer stops the next save (td-1vfz). The Error goes to the zone once, the changes stay pending, and the next save and flush send them again. (5) In lib/sync/coordinator.dart one helper, _refresh, does the refreshes of _sync, resolve and recoverKept. A refresh that fails stops nothing else. A sync whose refresh failed ends as RecordSyncFailure.unreadable, and a choice that was saved is never reported as not saved (td-w0wc). (6) lib/reader did not change. The _message slot did not change.

Verification, through nix develop. test/foundation/serial_queue_test.dart, 9 tests: against a plain future chain 4 failed, against a chain that hides failures the zone test failed, and all 9 pass now. test/playback/save_queue_test.dart, 5 tests: all 5 failed against the old write chain, and all 5 pass now. test/playback/command_queue_test.dart, 11 tests: the test that also passed on the old code was folded into its group, and 3 tests were added that state behavior that already held. They pass, and each fails against a mutant: setSpeed queued as a records command fails the speed test, and _inCommandOrder without the binding rule fails both tests of an earlier binding. test/sync/refresh_after_sync_test.dart, 20 tests: 9 failed against the old coordinator (8 new ones and the changed expectation), and all 20 pass now. flutter test test/foundation test/playback test/sync test/durability: 756 passed, 2 skipped (both ask for a pinned shell tool), 0 failed. flutter test on the 22 other test files that build a Playback or a RecordSync, or that import main.dart, the app shell, timeline.dart or records_screen.dart: 208 passed, 1 skipped (it asks for BOOKFIN_JOURNAL_GROWTH_EVIDENCE), 0 failed. No test failed because a dropped ArgumentError now reaches the zone. The other 168 test files were not run. dart analyze on the 7 changed Dart files: no issues.

New ticket: t5-6lnm (a history entry or a bookmark that is gone before its command runs).

**2026-11-13T02:37:44Z**

Second review fixes. Worktree /Users/alexispurslane/.t3/worktrees/bookfin/t3-a3b8c27b, branch t3/fix-playback-shutdown-sync-refresh. Imported d8e70cc4, a5ca4d5b and 26b51746 as cecd5083159d3bdcbdaaefb95bf419a7e3c69fa8, 45ff1b6e7cec625386e45262705da1aaeb7227c9 and 08a9fc1d05bb816e4bbcfb1e5a8db507e3e6e09a.

Finding 1. close calls the existing flush path after stop. flush retries pending changes for every account, including an account that was unbound. A retry returns its own Error or Exception to its caller. Background saves still show an Exception as save status. They send an Error to the zone once. The serial queue still never fails. A failed close completes teardown in finally and leaves pending changes in memory. The engine, subscriptions and signals are released. The caller receives the failure and can still flush the retained instance. A successful flush after close does not notify disposed signals. No Error is caught to recover.

Callers inspected. lib/main.dart uses flush for background transitions and desktop exit. Desktop exit reports a save failure and exits. AccountBinding changes accounts with bind and does not dispose Playback. No production caller in lib closes Playback. pause and stop keep the instance and its pending records, and normal storage failures remain visible in save status. bind keeps pending records under their original account. This made the all-account retry necessary at the final flush. No path that runs inside either Playback queue waits for a new run on that same queue.

Finding 2. RecordSyncFailure.refreshFailed means the exchange with Jellyfin succeeded but a writer could not refresh its records. It advances the last successful exchange time. The status strip says Synced, or shows waiting choices, instead of Not syncing. The new banner title is "Synced records could not be shown". Its text is "The sync finished. Bookfin shows the new records after the next sync." Every switch over failure kinds handles the new kind explicitly. The settings and catalog screens and the alert and label code hold no other switch over this enum. The next successful refresh clears the failure through the existing sync path. No outcome type redesign was needed.

Smaller items. SerialQueue.run now accepts only Future<void> work. Its documentation describes the wait on itself when a run awaits another run on the same queue. The next-save assertion now runs before cleanup. The save tests use the real LocalResumeStore and read saved records through a fresh store. New tests cover the stop event, both kinds of retry failure, overlapping position and history saves, and pending records after account changes. The refresh retry test uses real staleDomains tracking and the HTTP fixture. Two widget tests exercise the new banner and status strip.

Red evidence before implementation. save_queue_test: 7 passed and 5 failed. Both close reports the final Error and keeps the stop event pending and close reports the final Exception and keeps the stop event pending returned normally instead of throwing. flush reports the Exception from its own retry save returned normally. close retries a failed stop save and stores its history left unsavedChanges true. close saves pending records of an account that was unbound read an empty bookmark list. The Error form of the flush test and the overlap test already passed. They protect existing behavior.

Red sync run: 18 passed and 6 failed. Three changed cause tests received unreadable instead of refreshFailed. advances the last successful sync time despite the failed refresh retained 16:29 instead of 16:30. a failed refresh offers the next sync instead of restart advice found no new banner. a failed refresh still shows the successful exchange in the status strip found Not syncing. the next sync refreshes the real stale listening domain and clears its failure already passed. It protects existing behavior with the real store. No new test failed from a missing reference. The cause tests compared the enum name before the enum member existed, then used the member after implementation.

Focused green run: flutter test test/foundation/serial_queue_test.dart test/playback/save_queue_test.dart test/sync/refresh_after_sync_test.dart test/sync/refresh_retry_test.dart --concurrency=2 --reporter expanded. 44 passed, 0 failed, 0 skipped.

First broad run: 796 passed, 4 failed and 2 skipped. The four cleanup failures were the status shows a records save that failed, SQLite choosing the 900 ms resume survives coordinator flushes without moving paused audio, SQLite choosing the 100 ms resume survives coordinator flushes without moving paused audio, and SQLite a displayed conflict that changed before the tap gives a recoverable result. The full-disk test now expects the close Exception. The SQLite fixture now closes Playback before closing and deleting the database. All four pass in the final run.

Final verification ran through nix develop --command bash /tmp/boo-x1zf-verify.sh. Each Flutter run used --concurrency=2 --reporter json. No whole-suite run, device use, coverage run, mutation run, push or ticket closure.

Commands inside the Nix dev shell:
flutter test test/foundation test/playback test/sync test/durability test/app --concurrency=2 --reporter json
Result: 800 passed, 0 failed, 2 skipped.
flutter test test/appearance/appearance_sheet_test.dart test/appearance/production_city_test.dart test/boot_shell_test.dart test/catalog/book_page_test.dart test/catalog/library_view_test.dart test/catalog/shell_rebuild_test.dart test/development/gallery_test.dart test/foundation_test.dart test/reader/dock_history_test.dart test/reader/dock_test.dart test/reader/history_pages_test.dart test/reader/landing_words_test.dart test/reader/records_test.dart test/reader/shared_appearance_test.dart test/research/journal_growth_measurement_test.dart test/settings/screen_test.dart test/speech/hearing_policy_test.dart --concurrency=2 --reporter json
Result: 157 passed, 0 failed, 1 skipped. The 17 files cover the remaining tests that construct Playback or RecordSync, read RecordSyncFailure, or import main, the app shell, timeline or records_screen.
dart analyze lib/foundation/serial_queue.dart lib/playback/playback.dart lib/sync/coordinator.dart lib/sync/screen.dart test/foundation/serial_queue_test.dart test/playback/save_queue_test.dart test/playback/signals_test.dart test/sync/coordinator_test.dart test/sync/refresh_after_sync_test.dart test/sync/refresh_retry_test.dart
Result: No issues found. dart format on the same ten files and git diff --check also passed.

Skipped tests: durable ordinary-account records and offline changes survive plugin upgrade: null, two durable ordinary-account clients merge offline edits through the actual plugin, and measure incremental saves and acknowledgments while retaining every original action. The first two need the pinned integration tools. The third needs BOOKFIN_JOURNAL_GROWTH_EVIDENCE. Flutter also reported missing iphoneos and iphonesimulator SDKs. No requested test depends on those SDKs.

Every review item was applied. No user decision is needed. The playback message union, lib/reader, boo-23ji and t5-6lnm were not changed. The orchestrator owns integration, coverage, mutation testing and ticket closure.

**2026-11-13T02:41:46Z**

Orchestrator, 2026-11-12: merged into main as four commits, after two reviews and two rounds of fixes. One more change by the orchestrator on top: the last fixer made `flush()` and `close()` throw the Exception of a failed save. That gave every caller that drops the future of `flush()` an uncaught error for an expected failure such as full storage (the app when it goes to the background, the Retry action of the save notice), and it differed from the flush of the reader session. The contract is now: an Exception from a save is the save status and `flush()` and `close()` complete normally. An Error from a save is a bug and goes to the caller of `flush()` and `close()`. Verification: the tests "close keeps as the save status the final Exception", "flush keeps as the save status the Exception of its own retry save" and "the status shows a records save that failed" failed before this last change and pass after it. test/foundation, test/playback, test/sync, test/durability and test/app: 800 passed, 2 skipped. td-1vfz and td-w0wc are fixed by this ticket. Follow-up: t5-6lnm.

**2026-11-13T02:44:40Z**

Whole suite on main at 4f36c1b7: `nix develop --command flutter test`, 3092 passed, 25 skipped, 0 failed.
