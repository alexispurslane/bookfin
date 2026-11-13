---
id: boo-2gse
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
# Start the catalog restore before the other data sources open

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: confirmed, size of the delay not measured. lib/main.dart:71-87 awaits `openSources` (appearance, Downloads, Playback with `AudioService.init`, covers) before `runApp`. `CatalogController` is built inside the widget tree (main.dart:260-269), so `restore()` starts only after that. The time to the saved library is the sum of the two, not the larger of the two. Build the controller in `runBookfin` with the other sources and start `restore()` before `await openSources`. Related: tf-mo5q, boo-8v53.

## Settled implementation scope, 2026-11-13

Parent inspection at `4c020d1e` confirms that the startup order still matches the finding. Start the existing local catalog restoration concurrently with opening the other data sources, before their completion can delay it. Hand the same controller and restoration work to the app; do not create a second catalog, restart restoration, duplicate refreshes, or add a second startup path. Keep one explicit owner for construction, lifetime and disposal. Preserve the existing caller-owned controller behavior used by tests and the gallery's avoidance of real account/server access.

Preserve cache-first display, the one-hour resume policy, expired-sign-in local access, account binding, and catalog-choice ownership. Inactive-account migration still waits until after the first frame and must retain its existing recovery notices and failure reporting. Catalog restoration, network refresh and migration retain their distinct dependencies: no network request or inactive-account migration may become a prerequisite for the first useful frame. Do not expand into the Android service-startup profiling or catalog-read profiling tickets, and make no measured Android speed claim.

Use the real startup coordination path in controlled tests. Prove a meaningful failure that the saved catalog cannot begin/complete while unrelated source startup is held; then prove it can after the fix. Cover the opposite completion order, exactly one restore/refresh, failed restoration or source opening, root disposal while work remains, supplied-controller ownership and gallery behavior where affected. Preserve local migration/notice tests and account/lifecycle tests. Avoid tests that exercise an unused helper instead of production startup. Extend the existing startup boundary only as required; no speculative bootstrap framework.

Primary ownership: `lib/main.dart`, `test/app/app_shell_test.dart`, `test/boot_shell_test.dart`, any narrow startup regression file and this ticket. Change catalog code only if its existing interface cannot support coherent ownership. boo-o3cm concurrently owns Downloads and AccountBinding; boo-3y46 owns remote record admission. Parent handles overlap. Read the integrated boo-jlhy, boo-7z9a and boo-721h behavior before moving startup code.

Required final checks through Nix: focused startup tests, `test/app test/catalog test/boot_shell_test.dart test/downloads test/playback test/sync`, affected analysis and formatting, and the full Flutter suite. Concurrency two; one heavy command at a time. Exactly one fresh read-only Astra reviewer at high; implementation and direct fixes use Astra at xhigh. No second reviewer, device work, browser work, coverage, mutations, deployment, push, PR or ticket closure. Parent owns integration, acceptance and hardening.

## Delegated task

Original base: `ed355cd7bce324ce109a0022a468cb3c462eb5c5`.
Client request ID: `bookfin-boo-2gse-astra-20261113-1`.
Task ID: `node:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-boo-2gse-astra-20261113-1`.
Child thread ID: `thread:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-boo-2gse-astra-20261113-1`.
Thread: <t3-thread://v2/38d3e8fa-8572-4c2a-8a3b-2eb7c344dfce/thread:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-boo-2gse-astra-20261113-1>.
Launch returned running on codex/gpt-6-astra with reasoningEffort xhigh. Branch and precise stage not yet reported. Build, one fresh read-only review and direct fixes are authorized. Completion delivery is automatic.

## Implementation and verification, 2026-11-13

Initial checkout inspection: `/Users/alexispurslane/.t3/worktrees/bookfin/t3-5b74c8a7`, branch `t3/catalog-restore-startup`, HEAD/original review base `ed355cd7bce324ce109a0022a468cb3c462eb5c5`, clean. No checkout creation, switch, reset or removal. This lead uses codex/gpt-6-astra at xhigh; the parent retains integration, acceptance, hardening and closure. `tk ready` and the dependency tree show no ticket dependencies; `tk start boo-2gse` retained its in-progress status.

`runBookfin` now constructs the local catalog and begins its existing restoration operation before waiting for the other sources. A private root constructor transfers that same controller, store and future to the existing root lifecycle. The root continues the existing refresh/migration path; it does not restart restoration. Startup disposes the controller if opening fails; after handoff the root owns disposal. The public constructor's supplied controllers remain caller-owned. Direct local-root callers retain their existing behavior. Gallery startup does not restore accounts or migrate their storage.

The root stops pending continuation work after disposal. A completed restoration does not start a refresh or migration after removal, and a migration already in progress does not reconcile through a removed root. Migration remains after restoration and the first frame, independent of network completion. Existing recovery notices and Flutter error reporting remain. No CatalogController, Downloads, AccountBinding, remote record admission, Android service or performance implementation changed.

The production startup boundary accepts replacements for native source opening, catalog construction/storage and record persistence. Tests call `runBookfin`, including the existing `openSources` coordinator with a held appearance restore. They use real catalog-controller behavior and catalog construction; only storage, server responses and the isolate scheduling boundary are controlled. The controller test observer counts restore/refresh/disposal operations; an illegal refresh after disposal is counted without entering its completed-restore retry loop, so the regression fails promptly. Existing catalog suites continue to test actual file stores and worker execution.

### Red-green and setup record

Every Flutter command used the project Nix shell and concurrency two. One heavy command ran at a time. Logs are in `/tmp`.

| Command or selection | Result | Log |
| --- | --- | --- |
| `nix develop --command flutter test --no-pub --concurrency=2 test/app/catalog_startup_test.dart --reporter expanded` | Initial setup failure: this fresh worktree had no package configuration. No meaningful red claimed. | `/tmp/boo-2gse-red-order.log` |
| `nix develop --command flutter pub get` | Passed; populated worktree dependencies without changing the lockfile. | `/tmp/boo-2gse-pub-get.log` |
| Same startup test command | Ordering assertion failed, but fixture errors also occurred: native SQLite factory was unavailable and asynchronous catalog work had not completed in fake time. No clean red claimed. | `/tmp/boo-2gse-red-order-2.log` |
| Same startup test command | Ordering assertion failed meaningfully; the opposite-order fixture still failed because the isolate work had not completed. Injected the existing inline hop boundary for these widget tests. | `/tmp/boo-2gse-red-order-3.log` |
| Same startup test command, expanded cases | Two ordering/ownership failures observed, then pending-disposal case stalled in repeated future callbacks. Interrupted only this command's confirmed Flutter runner PID 64748 with SIGINT. The runner exited 0 on interruption; this is not a passing run. | `/tmp/boo-2gse-red-startup.log` |
| Same startup test command, bounded post-disposal observer | 6 passed, 3 meaningful failures: catalog had not started while other sources were held; source failure had no catalog to dispose; removed root still attempted refresh. | `/tmp/boo-2gse-red-startup-2.log` |
| `nix develop --command bash -c 'dart format lib/main.dart test/app/catalog_startup_test.dart && flutter test --no-pub --concurrency=2 test/app/catalog_startup_test.dart --reporter expanded'` | Passed, 9 tests, after moving restoration ahead of source opening and adding ownership/disposal guards. | `/tmp/boo-2gse-green-startup.log` |
| `nix develop --command bash -c 'dart format lib/main.dart test/app/catalog_startup_test.dart && flutter test --no-pub --concurrency=2 test/app/catalog_startup_test.dart test/app/app_shell_test.dart test/app/resume_refresh_test.dart test/catalog/file_store_test.dart test/boot_shell_test.dart --reporter expanded'` | Passed, 60 tests, including 12 production-startup cases, migration failure/recovery and existing lifecycle/file-storage behavior. | `/tmp/boo-2gse-focused.log` |
| `nix develop --command bash -c 'dart format lib/main.dart test/app/catalog_startup_test.dart && flutter analyze --no-pub lib/main.dart test/app/catalog_startup_test.dart && dart format --output=none --set-exit-if-changed lib/main.dart test/app/catalog_startup_test.dart'` | Exit 1: two initializing-formal lint notices in the private constructor. Corrected directly; format check after analysis did not run in this attempt. | `/tmp/boo-2gse-analysis-format.log` |
| `nix develop --command bash -c 'dart format lib/main.dart test/app/catalog_startup_test.dart && flutter analyze --no-pub lib/main.dart test/app/catalog_startup_test.dart && dart format --output=none --set-exit-if-changed lib/main.dart test/app/catalog_startup_test.dart && flutter test --no-pub --concurrency=2 test/app/catalog_startup_test.dart test/app/app_shell_test.dart test/app/resume_refresh_test.dart test/catalog/file_store_test.dart test/boot_shell_test.dart --reporter expanded'` | Exit 0: no analysis issues, zero format changes, 60 tests passed. Includes a visible cached-book assertion while network and migration remain held. | `/tmp/boo-2gse-focused-final.log` |

The startup cases cover both completion orders, one restoration/launch refresh, migration after the first frame, a usable saved book during held network/migration, storage failure, migration failure with reconciliation, expired credentials, failed source opening before/after restoration, disposal while restoration/migration is pending, injected-controller ownership and gallery isolation. They do not measure Android speed. Native setup emitted the host's existing missing iOS SDK notices; no iOS build or device verification is claimed.

Required suites, full suite and the single fresh review are recorded below after they complete.

- Required affected suites: `nix develop --command flutter test --no-pub --concurrency=2 test/app test/catalog test/boot_shell_test.dart test/downloads test/playback test/sync --reporter expanded` — exit 0, 1,460 passed, 3 existing skips, zero failures, 1:22. Log: `/tmp/boo-2gse-required.log`.
- Complete Flutter suite: `nix develop --command flutter test --no-pub --concurrency=2 --reporter expanded` — exit 0, 3,407 passed, 27 existing skips, zero failures, 4:53. Log: `/tmp/boo-2gse-full.log`.
- `git diff --check` — passed. Production and tests did not change during the required and complete suite runs. All owned commands completed before the review launch.

No outstanding product/design forks. No devices, browser, coverage, mutation campaign, push, PR, deployment, ticket closure or worktree removal. No work on the concurrently owned Downloads/AccountBinding or unreadable remote-record admission paths.

## Single fresh review and handoff, 2026-11-13

The authorized read-only reviewer completed on codex/gpt-6-astra with reasoningEffort high, shared isolation and async mode. It reviewed the complete original-base `ed355cd7bce324ce109a0022a468cb3c462eb5c5` to implementation-head `bfc769d02e69a0713021895e31e409d15f3e6138` diff, real callers, contracts, tests and saved logs. It confirmed a clean checkout before and after review. It made no edits and ran no builds, tests, commits, checkout operations or children.

Reviewer: <t3-thread://v2/38d3e8fa-8572-4c2a-8a3b-2eb7c344dfce/thread:delegated-task:command%3Amcp%3A97991ec6-2bd3-4524-b37e-41512c2d9ad6%3Adelegate-task%3Aboo-2gse-review-astra-20261113-1>

Task ID: `node:delegated-task:command%3Amcp%3A97991ec6-2bd3-4524-b37e-41512c2d9ad6%3Adelegate-task%3Aboo-2gse-review-astra-20261113-1`.

| Assessment | Original verdict | Evidence | Findings |
| --- | --- | --- | --- |
| Correctness | pass | Startup ordering and ownership in main.dart; pending-disposal guards; existing restoration, refresh and controller-disposal contracts. No substantiated regression. | None |
| Ticket fulfillment | pass | Twelve production-startup cases and inspected logs; existing migration, binding, expired-credential and one-hour resume tests. No material in-scope requirement remains unverified. | None |
| Software design | pass | One controller/operation with private ownership transfer; public injected-controller ownership preserved. Satisfies User single owner/coherent model, Ousterhout information hiding and Muratori feed-the-existing-path rules. No parallel catalog mechanism or speculative framework. | None |

Overall verdict: pass. No fixes or second review were needed. These are the reviewer's original verdicts.

Validation limits are retained: the reviewer inspected logs and source rather than executing tests; startup tests control native dependencies and worker scheduling; Android acceptance and measured launch-time improvement are unverified and outside scope; coverage and mutation testing remain with the parent after acceptance.

This follow-up commit changes only ticket evidence. Production and tests are exactly the reviewed and fully verified implementation commit. All lead commands and the single reviewer finished before handoff. The ticket remains in progress for parent integration and closure.
