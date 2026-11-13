---
id: boo-rw9z
status: in_progress
deps: []
links: []
created: 2026-11-12T23:41:00Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Make Playback.flush wait only for record writes

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: confirmed. `flush()` (lib/playback/playback.dart:1756-1770) awaits the whole command queue and `reports.idle`, the chain of Jellyfin progress reports with 20-second timeouts. `SyncCoordinator` awaits `flush()` before each sync (lib/sync/coordinator.dart:225, 294). A slow network delays a sync that the user started, and a command that never returns blocks every later sync. `flush` saves the current place and awaits only the record writes. A caller that also needs the reports drained asks for that separately.

## Settled implementation scope, 2026-11-13

The integrated boo-hmrp changes already removed the wait for live Jellyfin reports. Preserve that implementation and its regressions. At main `25a2fde5`, `Playback.flush()` still waits for `_operations.idle`; `_binding` can also wait for earlier audio commands. The remaining task is to make local record persistence independent of an unfinished audio command, without inventing a second record writer or a second place authority.

Save the current confirmed place and changed records, await the corresponding local writes, and retain/retry failed writes under their original account. A requested seek or book that the decoder has not confirmed must not replace the confirmed place. Saving must work during a held load, seek or pause, and an account transition must not move old pending writes into the new account. Do not silently change command completion into a requirement that callers must invoke flush. Each command remains responsible for saving the records it produces. Inspect current callers that used flush as a command barrier and make each wait for its actual command when needed. Teardown still owns stopping playback, draining live reports and releasing resources. Preserve the existing ordinary-save-failure versus programming-error behavior.

Use controlled engine and storage waits to prove meaningful red-green behavior: flush finishes before an unrelated held audio command, an unconfirmed destination is not saved, local writes still delay flush until durable, failed pending writes survive and retry, account changes preserve ownership, and sync can start an exchange after local saves without waiting for the held command. Retain ongoing playback/upload cadence, history, Undo, record refresh merging and shared writer registration. Read `test/playback/save_queue_test.dart`, `test/playback/replacement_test.dart`, `test/sync/event_upload_test.dart` and actual lifecycle/sync callers before changing them.

Primary ownership: `lib/playback/playback.dart`, relevant playback/sync tests and this ticket. Change other callers only where this behavior requires it. boo-o3cm concurrently owns download restoration and AccountBinding; boo-3y46 owns unreadable remote-object admission. Do not duplicate either task. Parent resolves integration overlap. The pending product decision in boo-56h7 does not belong here.

Required checks through Nix: focused behavior tests, `test/playback test/sync test/durability test/app` plus relevant reader persistence/records tests, affected analysis and formatting, and the full Flutter suite. Flutter concurrency two; one heavy command at a time. Implementation and fixes use codex/gpt-6-astra at xhigh. Exactly one fresh read-only reviewer uses the same model at high. No second review, coverage, mutation testing, devices, browser work, push, PR, deployment or ticket closure. Parent owns integration, acceptance and hardening.

## Delegated task

Original base: `db45fcaa5e13cab6eb2de210d5d0403623f4a31b`.
Client request ID: `bookfin-boo-rw9z-astra-20261113-1`.
Task ID: `node:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-boo-rw9z-astra-20261113-1`.
Child thread ID: `thread:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-boo-rw9z-astra-20261113-1`.
Thread: <t3-thread://v2/38d3e8fa-8572-4c2a-8a3b-2eb7c344dfce/thread:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-boo-rw9z-astra-20261113-1>.
Launch returned running on codex/gpt-6-astra, reasoningEffort xhigh. Branch and precise stage are not yet reported. Build, one fresh read-only review, then direct fixes are authorized. Completion delivery is automatic; do not poll.
