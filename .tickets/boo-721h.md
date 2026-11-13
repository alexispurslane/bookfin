---
id: boo-721h
status: in_progress
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

The single fresh review is next: codex/gpt-6-astra, reasoningEffort high, read-only shared checkout. No additional reviewer or re-check is authorized. The parent retains acceptance, hardening, integration and closure.
