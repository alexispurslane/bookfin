---
id: boo-s11s
status: in_progress
deps: [boo-hmrp]
links: [boo-f4xm, boo-0931, boo-hmrp, t6-il6y, t8-dqir]
created: 2026-11-12T23:41:00Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Upload and receive personal records in batches

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: confirmed. lib/playback/store.dart:458-489 sends one HTTP PUT and one local SQLite transaction for each pending action, oldest first. The plugin refuses a discovery page above 4 objects (plugin/Bookfin.Storage/StorageController.cs:24-27), and the client stops after 128 pages. One hour of listening queues about 3,600 actions. The next sync then makes 3,600 round trips in sequence, and the newest place arrives last. A receiving device takes at most 512 actions for each sync, and each cut-off sync reports "Sync did not finish". Step 1 needs no plugin change: upload with bounded concurrency and acknowledge each batch in one transaction. Step 2 changes the plugin API (a batch PUT and larger discovery pages, selected by plugin version). The November 3 decision in t6-t9po kept that API fixed, so step 2 needs a user decision.


## Notes

**2026-11-13T01:09:38Z**

User decision, 2026-11-12: do both steps, client first. Step 1: bounded concurrent uploads and one acknowledgment transaction for each batch, with no plugin change. Step 2: a batch upload and discovery pages of hundreds of objects, selected by plugin version, with the 4-object shape as the fallback. This replaces the part of the November 3 decision (t6-t9po) that kept the plugin API fixed. The decision to keep every action stays. Step 2 changes what t6-il6y (in progress) packages, so coordinate with that ticket.

## Integration prerequisites and package coordination

The parent inspected t6-il6y before launching this work. Its local deployment candidate is already integrated; that ticket remains open for deployment and broader acceptance, not for an active implementation branch. This ticket owns the additive batch API, its package version/metadata and documentation, and disposable compatibility evidence. Keep the existing plugin identity, database, retained actions, and v1 clients usable. Do not publish or install on a live server. Record the new candidate and exact compatibility evidence in t6-il6y when complete; its earlier 0.1.1.0 proof does not establish compatibility of the changed API.

The current transport is lib/sync/transport.dart after boo-f4xm. The store remains the durable acknowledgment owner; the event scheduler from boo-hmrp remains unchanged. Build and commit the client-only step before the additive plugin step so the fallback can be inspected separately. Use the pinned tool/research/sync dev shell and existing disposable plugin fixtures for C# and packaging checks. Preserve partial-success retry, account isolation, deletion barriers, conflicts, cursor transactionality, and every immutable action. No record compaction or startup snapshot work belongs here.


## Astra implementation launch

Original review base: 1de1ed6ba8a0bd69af70b2123f7fd8a63cedd48f. Implementation and direct fixes: codex/gpt-6-astra, reasoningEffort xhigh, separate T3 worktree. One fresh shared read-only reviewer is authorized on the same provider/model with reasoningEffort high; no other stage agents. Scope covers both approved steps in order, with a separate client-only commit, package coordination, and disposable compatibility checks. Parent owns integration and closure.

Client request ID: bookfin-boo-s11s-astra-20261113-1
Task ID: node:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-boo-s11s-astra-20261113-1
Child thread ID: thread:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-boo-s11s-astra-20261113-1
Thread: <t3-thread://v2/38d3e8fa-8572-4c2a-8a3b-2eb7c344dfce/thread:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-boo-s11s-astra-20261113-1>
Launch status: running; stage not yet reported. Completion will be delivered automatically.

## Step 1: bounded existing-API uploads

Inspected clean worktree `/Users/alexispurslane/.t3/worktrees/bookfin/t3-e16914e3`, branch `t3/batch-personal-record-sync`, original HEAD `1de1ed6ba8a0bd69af70b2123f7fd8a63cedd48f`. Read project rules, scope, dependency tree, and required design/TDD/role instructions. No checkout manipulation or device work.

Transport sends at most four existing v1 PUT requests concurrently, waits for the group, validates each confirmation independently, and passes successful identities to LocalResumeStore. The store acknowledges the group in one durable transaction. Every immutable action stays retained. Failure leaves only unconfirmed actions pending; a failed acknowledgment transaction rolls back the entire group. Server-copy recovery keeps its existing durable owner. RecordSync scheduling is unchanged.

Five behavior tests first failed for sequential upload, per-object commit, partial acknowledgment rollback, and skipped later confirmations. Log `/tmp/boo-s11s-step1-red.log`. A first test attempt could not load without dependency configuration; `nix develop --command flutter pub get` completed (`/tmp/boo-s11s-pub-get.log`). This setup failure is not red evidence. Focused green: 54 tests in `/tmp/boo-s11s-step1-green.log`.

The first affected run passed 1,111 tests with two external-fixture skips and one old sequential-retry expectation failure (`/tmp/boo-s11s-step1-affected.log`). Updated that test to preserve verified partial successes and use a deterministic interrupted request. An initial analysis also found an unused import and null-aware-element lint; both fixed.

Final command: `nix develop --command bash -c 'dart format test/sync/format_retry_test.dart lib/sync/transport.dart test/sync/batch_transport_test.dart && flutter analyze --no-pub lib/sync/transport.dart lib/playback/store.dart test/sync/batch_transport_test.dart test/sync/format_retry_test.dart && flutter test --no-pub --concurrency=2 test/sync test/playback test/durability test/catalog --reporter expanded'`. Result: analysis clean; 1,112 passed, 2 existing external-fixture skips, no failures, 1:08. Log `/tmp/boo-s11s-step1-affected-final.log`. Full suite and fresh review follow both steps. Host checks only; absent iOS SDK notices are unrelated to these host tests.
