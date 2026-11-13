---
id: boo-721h
status: closed
deps: []
links: []
created: 2026-11-12T23:41:00Z
type: bug
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Keep downloaded books, playback and the reader usable after a 401

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: path confirmed, trigger plausible. lib/catalog/transport_io.dart:81-83, lib/catalog/controller.dart:728-735, lib/app/account_binding.dart:91-97. Any 401 during a background refresh clears the session and the library, deletes the saved token, binds Playback and the reader to no account (which stops audio and closes the book), and pops every route to the sign-in form. A revoked token or a sign-in proxy with an expired cookie triggers it. Engine rule 2 says that cached information is fully usable. Separate the local account (identity, saved library, downloads, records) from the state of the server credential. A 401 marks the credential as "needs sign-in" and stops only the work that needs the server. Delete the token only on an explicit sign-out or when a new sign-in replaces it.

## Astra implementation scope

Use the settled distinction between the local account and whether its server credential can be used. A background 401 must preserve the local account, cached books, downloaded files, active local playback, the open reader and durable personal records. Keep local saves and pending sync actions working. Mark that sign-in is needed and suspend work that requires the rejected credential. Retain the saved token until explicit sign-out or successful replacement; a failed or cancelled sign-in must not implicitly erase the local account. Successful sign-in to the same account resumes server work without losing the current book or saved place. A different account and explicit sign-out retain account isolation.

Provide a usable sign-in-again action through the existing account UI and reuse its form and glass components. Preserve existing visual structure and narrow subscriptions. A 403 that explicitly denies library access remains a distinct condition; this ticket does not grant access that the server has denied. Preserve the one-hour resume freshness rule, cache-first launch, and integrated record-upload scheduling. The concurrently running boo-7z9a owns separation of catalog choices from its cache; do not duplicate that migration. The parent resolves integration overlap.

Required meaningful red-green evidence covers a background 401 during active local playback and reading, subsequent local saves, restart from the retained account, no automatic server work with the rejected credential, failed/cancelled/successful reauthentication, explicit sign-out, a changed account, and obsolete request completion. Exercise real controllers and bindings as well as the sign-in UI. Update tests that require automatic sign-out after 401. Run catalog, app, downloads, playback, reader persistence and sync checks, affected analysis/format, and the full Flutter suite at concurrency two through Nix, one heavy command at a time.

Implementation and direct fixes use codex/gpt-6-astra with reasoningEffort xhigh. Exactly one fresh read-only reviewer uses the same model at high. Parent owns integration, acceptance, hardening and closure. No device work, coverage, mutations, push, PR or live deployment.

## Delegated task

Original base: 025937e5d768b6bb69030f030e20e8a809d729ea.
Client request ID: bookfin-boo-721h-astra-20261113-1
Task ID: node:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-boo-721h-astra-20261113-1
Child thread ID: thread:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-boo-721h-astra-20261113-1
Thread: <t3-thread://v2/38d3e8fa-8572-4c2a-8a3b-2eb7c344dfce/thread:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-boo-721h-astra-20261113-1>
Launch returned running on codex/gpt-6-astra with reasoningEffort xhigh. Stage and branch not yet reported. Completion delivery is automatic.

## Implementation evidence (Astra xhigh, 2026-11-13)

Checkout identity before edits: `/Users/alexispurslane/.t3/worktrees/bookfin/t3-70f9bbde`, branch `t3/preserve-local-access-after-401`, HEAD/base `025937e5d768b6bb69030f030e20e8a809d729ea`, clean. No checkout was created, switched or reset. This ticket remains in progress; the parent owns integration and closure.

The retained session now separates local account identity from a shared, monotonically rejected server credential. Policy validation retains that credential's signal. A 401 retires server work and persists rejection with the original token; same-account authentication replaces the credential without replacing local identity. Downloads, live playback reporting, record sync and cover requests follow that signal. A rejection cannot cancel local catalog restoration or authentication with a replacement credential. Reader identity follows account scope, not token text. Local conflict choices continue to update their visible records without recording a server success.

Settings offers sign-in again and account replacement in the existing glass sheet with the shared sign-in fields. Opening, failing or cancelling this form retains the current account. Explicit sign-out and accepted different-account authentication retain account isolation. A new credential retries missing cover images in the current view. A 403 retains its existing distinct library-denial behavior.

The integration regression uses actual downloads, verified local files, the EPUB parser, Playback, ReaderSession, AccountBinding and LocalResumeStore. Only the audio device and catalog server are fixtures. It saves after rejection, replaces or signs out of the account, and restores a saved place and bookmark through a fresh record-store reader. Additional HTTP fixtures exercise Jellyfin's 401/403 handling, download restoration and suspension, playback reports, and record uploads on both preferences and SQLite.

No catalog-choice migration or native-record-startup implementation was changed. Parent integration overlap includes `lib/catalog/controller.dart` and the catalog tests (boo-7z9a); `lib/reader/session.dart` changes only account identity at bind, with no startup migration changes (boo-0931). Other touched shared paths include account binding, covers, record sync and settings.

### Red-green and iteration record

All Flutter commands used `nix develop --command flutter test`, concurrency 2, one heavy command at a time. Logs retain full output in `/tmp`. No devices, browser, coverage, mutation campaign, deployment, push or PR was used.

| Log under `/tmp/` | Result and explanation |
| --- | --- |
| `boo-721h-red-catalog.log` | 24 passed, 5 meaningful failures: retained local catalog, restart suspension, cancellation, failed replacement and invalid replacement. |
| `boo-721h-red-binding.log` | 3 meaningful failures: a background 401 stopped actual Playback through AccountBinding before each account transition. This test was then strengthened to real downloaded files and LocalResumeStore. |
| `boo-721h-red-ui.log` | Meaningful failure: opening account replacement immediately removed Alice's account. |
| `boo-721h-green-1.log` | 61 passed: catalog, binding and sign-in UI. |
| `boo-721h-red-sync-replacement.log` | 2 fixture failures, not red evidence: a helper expected a resolved resume while the fixture still had a conflict. |
| `boo-721h-red-sync-replacement-2.log` | 2 meaningful failures: pending local actions remained after successful sign-in returned the same token text. Fixed by including credential rejection in the binding comparison. |
| `boo-721h-green-boundaries.log` | 113 passed; integration test failed compilation because the strengthened loader passed VerifiedFile instead of its URI. Corrected the test. |
| `boo-721h-red-obsolete-response.log` | Meaningful failure: a delayed successful response was accepted after rejection. Added response-time credential guard. |
| `boo-721h-green-transitions.log` | 67 passed, including real file/record integration and both sync stores. |
| `boo-721h-required-1.log` | 1,413 passed, 3 skipped, 1 old expectation failed: `test/app/resume_refresh_test.dart`, “an expired sign-in stays signed out on return”. Updated to retained local account and no server refresh. |
| `boo-721h-red-local-choice.log` | No matching tests (exit 79): the insertion script did not match a formatted test declaration. No implementation changed. |
| `boo-721h-red-local-choice-2.log` | 2 meaningful failures: local resolution left an obsolete visible conflict while rejected. |
| `boo-721h-green-local-choice.log` | 28 passed: local conflict refresh and resume behavior. |
| `boo-721h-red-cover-retry.log` | Meaningful failure: current-view cover stayed missing after successful sign-in. |
| `boo-721h-green-cover-retry.log` | All 13 cover widget tests passed. |
| `boo-721h-analysis-1.log` | 12 lint notices: braces, import and initializing formal. Fixed. |
| `boo-721h-red-rejection-races.log` | No matching tests (exit 79): a formatted declaration again did not match the insertion anchor. No implementation changed. |
| `boo-721h-red-rejection-races-2.log` | 2 meaningful failures: rejection cancelled local restore and replacement authentication. |
| `boo-721h-green-rejection-races.log` | 63 passed: controller and sign-in UI. |
| `boo-721h-analysis-2.log` | Affected analysis: all 24 changed Dart files, no issues. |

The focused red commands selected the named tests with `--plain-name` or `--name`; the initial catalog and binding red commands ran their whole files. Flutter printed the host's missing `iphoneos` and `iphonesimulator` SDK notices during dependency/build-hook setup. No iOS verification is claimed. The complete final commands and review result follow below.

### Final required checks before review

- `nix develop --command flutter test --no-pub --concurrency=2 test/catalog test/app test/downloads test/playback test/sync test/settings test/reader/persistence_test.dart test/reader/records_test.dart test/reader/unread_records_test.dart test/reader/session_test.dart test/reader/catalog_flow_test.dart test/reader/pdf_session_test.dart test/reader/kept_page_session_test.dart test/reader/survey_session_test.dart` — passed, 1,419 tests and 3 existing integration skips; `/tmp/boo-721h-required-2.log`.
- `nix develop --command flutter analyze --no-pub lib/app/account_binding.dart lib/catalog/book_cover.dart lib/catalog/controller.dart lib/catalog/covers_io.dart lib/catalog/jellyfin.dart lib/catalog/screen.dart lib/downloads/local_downloads.dart lib/playback/reporting.dart lib/reader/session.dart lib/settings/screen.dart lib/sync/coordinator.dart test/app/credential_access_test.dart test/app/resume_refresh_test.dart test/catalog/book_cover_test.dart test/catalog/catalog_signals_test.dart test/catalog/controller_test.dart test/catalog/covers_test.dart test/catalog/jellyfin_test.dart test/catalog/screen_test.dart test/catalog/store_test.dart test/downloads/transfer_test.dart test/playback/reporting_test.dart test/sync/coordinator_test.dart test/sync/fixture.dart` — passed, no issues; `/tmp/boo-721h-analysis-2.log`.
- `git diff --check` — passed.

Final inspection added one cache-preservation regression after the first full pass: same-account sign-in after a failed catalog restore skipped the saved-catalog readability guard. `/tmp/boo-721h-red-unreadable-restore.log` records a meaningful failure (the unreadable file was replaced). The implementation now retries the saved-catalog read when there is no usable in-memory cache. `/tmp/boo-721h-green-unreadable-restore.log` records all 34 controller tests passing. This retains the original explicit-refresh requirement without introducing the concurrent catalog-choice migration.

The first full suite passed 3,319 tests, with 26 existing skips (`/tmp/boo-721h-full-1.log`). Skips concern optional EPUB corpus/benchmark fixtures, external plugin fixtures and existing opt-in platform checks. Final reruns after the readability fix are recorded below. The final affected analysis has no issues (`/tmp/boo-721h-analysis-final.log`, same explicit 24-file command above). Final format verification used `nix develop --command dart format --output=none --set-exit-if-changed` followed by the same 24 Dart paths: exit 0, zero changed files (`/tmp/boo-721h-format-check.log`).

- Final required suites: the exact required-suite command above passed 1,420 tests with 3 existing skips, exit 0 (`/tmp/boo-721h-required-final.log`).
- Final complete suite: `nix develop --command flutter test --no-pub --concurrency=2` — passed, 3,320 tests with 26 existing skips, exit 0 (`/tmp/boo-721h-full-final.log`).
- `git diff --cached --check` — passed. All owned commands finished before the review launch.

The single fresh review used codex/gpt-6-astra, reasoningEffort high, in the read-only shared checkout. Its findings and the single fix stage are recorded below. No additional reviewer or re-check is authorized. The parent retains acceptance, hardening, integration and closure.


## Review and single fix stage (Astra xhigh, 2026-11-13)

The one authorized fresh reviewer (codex/gpt-6-astra, reasoningEffort high) completed a read-only review of all 25 changed files from original base `025937e5d768b6bb69030f030e20e8a809d729ea` to implementation commit `af9245a20b879e167f3a84c0c39eee8a573ceb02`. Reviewer task: `node:delegated-task:command%3Amcp%3Ae4c85911-8c9d-4525-91a0-5e898028a057%3Adelegate-task%3Aboo-721h-review-astra-20261113-1`. It edited nothing, ran no builds or tests, changed no checkout, and started no agents. No second review was launched.

The fix stage confirmed the same worktree and branch, clean at `af9245a20b879e167f3a84c0c39eee8a573ceb02`, before editing. Implementation and direct fixes used codex/gpt-6-astra, reasoningEffort xhigh. No design fork arose.

| Review assessment | Original verdict | Evidence and gap identified by the reviewer | Fix disposition |
| --- | --- | --- | --- |
| Correctness | changes-required | Existing playback, reading, save, restart and isolation tests passed; replacement races R1–R3 remained. | All three findings reproduced with behavioral failures, then resolved below. |
| Fulfillment | changes-required | Shared sign-in form, glass sheet, distinct 403, cache-first restore and upload scheduling were present; durable replacement, obsolete-request isolation and cover recovery were incomplete. | R1–R3 repaired those gaps; required checks rerun after fixes. |
| Design | changes-required | Local identity was separate from credential rejection, with controller-owned effects and narrow signals; R2 showed inconsistent credential identity across consumers. | JellyfinSession now owns credential identity; all affected consumers use it. |

No assessment was marked unverified. There were no nonblocking findings. These original reviewer verdicts are retained; the evidence below resolves their findings without claiming a second review.

| Finding | Trigger and reviewed location | Resolution and evidence |
| --- | --- | --- |
| R1, high/P1, correctness and fulfillment | A 401 arrives while successful replacement credentials are being written; `lib/catalog/controller.dart:540,645`. The old rejected account could become the final stored value. | Credential persistence serializes successful adoption with the write. Queued rejection writes check credential ownership before writing. Two gated-write tests check both Alice-to-Alice renewal and Alice-to-Bob replacement, then restore and verify account, token, rejection state and catalog. Both failed before the fix and pass afterward. Existing cancellation, failed storage and explicit-sign-out tests remain passing. |
| R2, medium/P2, correctness, fulfillment and design | Same-account authentication returns the same token text, then an old request rejects the previous credential; `lib/catalog/controller.dart:108`, `lib/sync/coordinator.dart:143`, `lib/playback/reporting.dart:66`. Consumers could retain obsolete subscriptions. | `JellyfinSession.credentialIdentity` defines one credential lifetime: validation preserves it and successful authentication replaces it. Catalog equality, sync binding, live-report ownership/client reuse, downloads and covers all use that identity. Real CatalogController/AccountBinding/RecordSync tests on both preferences and SQLite prove pending local records upload after old rejection. A real HTTP live-report test proves current progress still reports. All three tests failed before the fix. The existing unchanged-refresh binding test now runs production policy validation and still proves no redundant binding or sync. This addresses User single authority, Ousterhout information hiding and Muratori scattered-concept evidence without changing local account identity. |
| R3, medium/P2, correctness and fulfillment | A replacement asks for a cover while the old credential's request is pending, then the old request fails with 401; `lib/catalog/covers_io.dart:47`. The current request reused the old failure. | DiskCovers tracks the credential that owns each pending plain/blurred request. A replacement waits for that write to finish, then reads its saved result or retries with its own credential. File writes remain serialized, including the blurred copy. Missing-image results belong to the credential that fetched them. Both delayed-fetch regressions failed before the fix and pass afterward; they verify current images, isolation from the old rejection, valid blur output, and offline reads through a fresh DiskCovers instance. |

### Fix-stage commands and results

Full outputs are retained under `/tmp`. Flutter concurrency stayed at two, with one heavy command at a time.

- Red: `nix develop --command flutter test --no-pub --concurrency=2 test/catalog/controller_test.dart test/catalog/covers_test.dart test/sync/coordinator_test.dart test/playback/reporting_test.dart --name 'rejection during secure replacement|same-token sign-in|does not inherit a pending old rejection'` — exit 1, all seven selected cases failed meaningfully for R1–R3; `/tmp/boo-721h-fix-red.log`. No fixture, syntax or missing-reference failures occurred.
- Focused green: `nix develop --command flutter test --no-pub --concurrency=2 test/catalog/controller_test.dart test/catalog/covers_test.dart test/sync/coordinator_test.dart test/playback/reporting_test.dart test/app/account_binding_test.dart` — exit 0, 96 passed; `/tmp/boo-721h-fix-green-1.log`.
- Formatting: `nix develop --command dart format lib/catalog/book_cover.dart lib/catalog/controller.dart lib/catalog/covers_io.dart lib/catalog/jellyfin.dart lib/downloads/local_downloads.dart lib/playback/reporting.dart lib/sync/coordinator.dart test/app/account_binding_test.dart test/catalog/controller_test.dart test/catalog/covers_test.dart test/playback/reporting_test.dart test/sync/coordinator_test.dart` — exit 0, 12 files formatted, six changed; `/tmp/boo-721h-fix-format.log`.
- Affected analysis: `nix develop --command flutter analyze --no-pub lib/app/account_binding.dart lib/catalog/book_cover.dart lib/catalog/controller.dart lib/catalog/covers_io.dart lib/catalog/jellyfin.dart lib/catalog/screen.dart lib/downloads/local_downloads.dart lib/playback/reporting.dart lib/reader/session.dart lib/settings/screen.dart lib/sync/coordinator.dart test/app/account_binding_test.dart test/app/credential_access_test.dart test/app/resume_refresh_test.dart test/catalog/book_cover_test.dart test/catalog/catalog_signals_test.dart test/catalog/controller_test.dart test/catalog/covers_test.dart test/catalog/jellyfin_test.dart test/catalog/screen_test.dart test/catalog/store_test.dart test/downloads/transfer_test.dart test/playback/reporting_test.dart test/sync/coordinator_test.dart test/sync/fixture.dart` — exit 0, no issues in all 25 changed Dart files; `/tmp/boo-721h-fix-analysis.log`.

- Required suites after fixes: `nix develop --command flutter test --no-pub --concurrency=2 test/catalog test/app test/downloads test/playback test/sync test/settings test/reader/persistence_test.dart test/reader/records_test.dart test/reader/unread_records_test.dart test/reader/session_test.dart test/reader/catalog_flow_test.dart test/reader/pdf_session_test.dart test/reader/kept_page_session_test.dart test/reader/survey_session_test.dart` — exit 0, 1,427 passed and 3 existing skips; `/tmp/boo-721h-fix-required.log`.
- Complete Flutter suite after fixes: `nix develop --command flutter test --no-pub --concurrency=2` — exit 0, 3,327 passed and 26 existing skips; `/tmp/boo-721h-fix-full.log`.
- Final format verification: `nix develop --command dart format --output=none --set-exit-if-changed lib/app/account_binding.dart lib/catalog/book_cover.dart lib/catalog/controller.dart lib/catalog/covers_io.dart lib/catalog/jellyfin.dart lib/catalog/screen.dart lib/downloads/local_downloads.dart lib/playback/reporting.dart lib/reader/session.dart lib/settings/screen.dart lib/sync/coordinator.dart test/app/account_binding_test.dart test/app/credential_access_test.dart test/app/resume_refresh_test.dart test/catalog/book_cover_test.dart test/catalog/catalog_signals_test.dart test/catalog/controller_test.dart test/catalog/covers_test.dart test/catalog/jellyfin_test.dart test/catalog/screen_test.dart test/catalog/store_test.dart test/downloads/transfer_test.dart test/playback/reporting_test.dart test/sync/coordinator_test.dart test/sync/fixture.dart` — exit 0, 25 files checked and zero changes; `/tmp/boo-721h-fix-format-check.log`.
- `git diff --check` and `git diff --cached --check` — passed; `/tmp/boo-721h-fix-diff-check.log` and `/tmp/boo-721h-fix-staged-check.log`.

All three blocking findings are resolved with evidence. There were no unexpected fix-stage verification failures; the seven initial failures were the required behavioral reproductions. The existing skip count did not change. All commands and the reviewer finished before handoff. The complete diff now includes 26 files, including the ticket and 25 Dart files. The parent still owns acceptance, hardening, integration and closure. No additional agents, devices, browser work, coverage, mutations, deployment, push, PR, checkout changes, ticket closure or worktree deletion occurred. Integration overlap remains as recorded above; neither concurrent migration was duplicated.

## Parent integration and assertion handling, 2026-11-13

Integrated onto main at `23af4216bcfc05b3627946dd346afa75a37febff`: implementation `663c6eb7`, review fixes `25a2fde5`. Conflicts in this ticket and `lib/catalog/controller.dart` preserve account-specific catalog choices, guarded restore/adoption, recovery notices, assertion propagation and the new credential lifetime. The second commit applied without conflicts. The parent inspected the complete implementation and fixes, their production callers and the saved review/check evidence. No additional reviewer was started.

The initial combined catalog-choice, controller, screen, account-binding, credential-access and sync-controller selection passed 139 tests. Exact command: `nix develop --command flutter test --no-pub --concurrency=2 test/catalog/choices_test.dart test/catalog/controller_test.dart test/catalog/screen_test.dart test/app/account_binding_test.dart test/app/credential_access_test.dart test/sync/coordinator_test.dart --reporter expanded`; log `/tmp/boo-721h-integrated-focused.log`.

The parent found two new asynchronous credential-save handlers that swallowed `AssertionError`, contrary to the project contract rule. Rejection persistence and cancelled-sign-in rollback now leave that failure uncaught, while preserving ordinary storage-failure handling. The credential-write queue still forwards failures to the original operation; its separate scheduling future does not duplicate them.

`nix develop --command flutter test --no-pub --concurrency=2 test/catalog/controller_test.dart --name 'failed contract|ordinary storage failure' --reporter expanded` reproduced both defects: two meaningful failures because no uncaught assertion arrived, and the ordinary-storage-failure control passed. Log: `/tmp/boo-721h-integrated-contract-red.log`. After the narrow fix, `nix develop --command bash -c 'dart format lib/catalog/controller.dart test/catalog/controller_test.dart && flutter test --no-pub --concurrency=2 test/catalog/controller_test.dart --reporter expanded'` passed all 39 tests, including both original-assertion identity checks. Log: `/tmp/boo-721h-integrated-contract-green.log`.

Parent affected/full checks and ticket closure remain pending at this commit. Android acceptance and hardening remain separate.

## Parent verification and closure, 2026-11-13

The assertion fix and its tests are committed as `e4854681`. No production changes followed that commit during parent verification. Integrated production comprises `663c6eb7`, `25a2fde5` and `e4854681`; later commits only record ticket scope and launch information.

| Check | Command and result | Evidence |
| --- | --- | --- |
| Required affected suites | `nix develop --command flutter test --no-pub --concurrency=2 test/catalog test/app test/downloads test/playback test/sync test/settings test/reader/persistence_test.dart test/reader/records_test.dart test/reader/unread_records_test.dart test/reader/session_test.dart test/reader/catalog_flow_test.dart test/reader/pdf_session_test.dart test/reader/kept_page_session_test.dart test/reader/survey_session_test.dart --reporter expanded` — exit 0, 1,489 passed, 3 existing skips, zero failures; 1:40 | `/tmp/boo-721h-integrated-required.log` |
| Complete combined suite | `nix develop --command flutter test --no-pub --concurrency=2 --reporter expanded` — exit 0, 3,389 passed, 27 existing skips, zero failures; 4:36 | `/tmp/boo-721h-integrated-full.log` |
| Format and analysis | `nix develop --command bash /tmp/boo-721h-integrated-checks.sh` — exit 0; all 25 changed Dart files format-clean and no analysis issues (3.5 seconds) | `/tmp/boo-721h-integrated-format.log`, `/tmp/boo-721h-integrated-analysis.log` |
| Complete integrated diff | `git diff --check 23af4216 HEAD` — passed | Parent command result |

The check script runs `dart format --output=none --set-exit-if-changed` and then `flutter analyze --no-pub` on the 25 Dart paths returned by `git diff --name-only 23af4216 HEAD -- '*.dart'`. This includes the merged catalog controller and all changed catalog/account tests. No checks overlapped another parent heavy command. Existing missing iOS SDK diagnostics remained nonfatal.

All parent commands finished. No unexplained test failures remain: the two initial assertion failures were the intended reproductions. The child review's original verdicts remain unchanged; direct resolutions and the parent's regression evidence establish completion without a second reviewer. The combined tests include the integrated catalog-choice migration, record restoration, PDF pager and upload scheduling.

Closed after integration and successful host verification. Device acceptance remains blocked by `t1-dth0`; `boo-zyx1` and `boo-737n` remain acceptance-open. Coverage and mutation testing await acceptance. No device retry, browser validation, push, PR, deployment or worktree deletion was performed.
