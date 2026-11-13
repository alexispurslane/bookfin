# boo-xyrl implementation evidence

Original base: `2f5f0393d4d5961627b7eb84f7c2f7725ab762aa`.
Worktree: `/Users/alexispurslane/.t3/worktrees/bookfin/t3-5d89a0e3`.
Branch: `t3/clear-account-data`. The checkout was clean at the original base.

## Scope and integration boundary

Settings confirms Clear data through the existing glass dialog. The confirmed
account and credential remain attached to the operation. The existing catalog
operation owner retires refresh results and blocks new refreshes until clearing
finishes. The initial save/upload must succeed before any removal. Downloads
still owns file deletion, cancellation, read holds, retained versions, and
containment checks. Covers deletes only the account directory after older image
loads can no longer recreate its files. Catalog deletion preserves corrections,
retained unreadable originals, login, and every other account. No record-store
file or global storage root is deleted.

New narrow interfaces:

- `RecordSync.requireUploaded(session)` joins the existing sync queue, flushes
  the account's live record writers, and checks durable pending uploads until
  acknowledged. It flushes writers again after each exchange, so a live save
  failure during an upload cannot hide behind an empty durable pending set.
  It throws on failure or account replacement instead of using a
  UI status as evidence of success. Live writers now report failed saves to
  their sync registration, while their ordinary lifecycle flush keeps its
  existing save-status behavior.
- `Downloads.clearAccount(session, beforeRemoval: ..., afterRemoval: ...)` uses the public
  `remove` and `removeRetained` boundaries. The callback repeats the required
  record check after file users release each download. It cannot request a
  download read. The reader's sync flush and record refresh therefore save
  personal records independently of derived page-image writes. Normal reader
  flush still saves both, in that order. The afterRemoval continuation keeps
  requests blocked while covers and catalog finish.
- `Covers.clear(account, afterRemoval: ...)` is now scoped. It blocks loads
  until the continuation publishes the empty catalog. There was no production
  caller of the former all-account method.
- `CatalogController.clearSavedLibrary(session, removeFiles: ...)` owns refresh
  retirement and the final cache deletion. It passes a guarded cache-deletion
  continuation to the file owners, which keep their protection until the empty
  library is published. `CatalogStore.clearCache` and
  `CatalogFiles.remove` remove only the cache's committed and partial file,
  preserving saved choices and retained unreadable copies.

The concurrent boo-39cu implementation is deliberately absent from this branch.
Its playing-audiobook protection must remain in the public Downloads removal
path when the parent integrates both branches. Clear data awaits that path and
rechecks records after its file hold ends; it introduces no second playback
removal mechanism. The parent must verify the combined playing-audiobook case.
A later failure stops further removal and is never reported as a completed
clear. Files already removed before a later failure are not reconstructed.

## Tests and archives

`commands.jsonl` records each build, test, format, analyze, and diff check with
its exact argument array, working directory, UTC times, exit status, base-diff
hash, and compressed and uncompressed log SHA-256 hashes. Every log is archived
as `<label>.log.gz`, including failed attempts. Starting at check 09, each check
also archives a hash manifest for every Dart source under lib and test. The
manifest hash is in the command record. Earlier checks retain the tracked diff
hash and their full logs. `run.py` produced these records sequentially.

Core tests use real LocalResumeStore preferences and SQLite stores, real
LocalCatalogStore preferences and disk files, real LocalDownloads files and
held reads, and real DiskCovers. Network boundaries use synthetic fixtures or
ControlledTransport. No live account, credential, or server was used.

The tests exercise confirmation cancellation, confirmation after account
replacement, required save/upload failures, late pending uploads, and changes
created while files are held. They check account replacement during saves,
uploads, file holds, and cover loading. They reopen stores and check retained
bookmarks, history, positions, another account's data, login, and appearance.
They also cover active transfers, old download versions, derived files, empty
retained manifests, stale refresh responses, and an already-started atomic
catalog write. Existing corruption/recovery tests are part of the affected
and full suites.

## Failed attempts and corrections

| Check | Result and resolution |
| --- | --- |
| 01 | Red: Settings had no Clear data row. The initial scroll lookup failed; the test now first asserts that the row exists. |
| 02 | Meaningful red: both real SQLite writers completed flush after a bookmark save failed. Registration now reports the retained unsaved change. The final tests cover preferences too. |
| 03 | Meaningful red: 26 required-upload and catalog-clear cases failed against compiling, inert interface scaffolds. |
| 04 | Meaningful red: seven file cases failed. The former cover clear removed another account and allowed a late plain cover to return; bulk download removal was inert. Two existing cases passed. |
| 05 | Two test-fixture failures: the synthetic upload observer assumed every action had a value, but replacing bookmarks also produces deletion actions. It now observes non-null titles while acknowledging every real action. 32 cases passed. |
| 07 | Test interaction failure: the Clear data text was partly outside the viewport. Ensuring the whole ListTile is visible fixed the tap. 20 cases passed. |
| 09 | Meaningful red: a retained manifest with no remaining media bytes was not removed. Bulk discovery now includes those manifests. |
| 11 | Test scheduling failure: the catalog write queue began in real time, but the UI check waited only in fake widget time. The test now uses the project's runUntil helper. Eight cases passed. |
| 14 | Three analyzer style findings in the new Settings action. Added braces. Final analysis is clean. |
| 16 | The first delayed-record experiment passed because its new save arrived before the initial upload loop ended. This did not prove the intended case. |
| 17 | Meaningful red after observing entry to the real removal boundary: all four preferences/SQLite delayed-record cases failed. The removal callback now repeats preservation after a held file is released. |
| 26 | Whitespace check found a trailing blank line in the new follow-up ticket. Removed it; no Dart change. |
| 18 | Meaningful red: reader record flush and refresh waited for a held derived page write. Both now use the record-only save path; ordinary flush still keeps the page. |

The complete command results, including successes, remain in commands.jsonl.
Exploratory path guesses that failed before finding the real files included
`lib/app.dart`, `lib/records/sync.dart`, `lib/catalog/catalog.dart`,
`lib/catalog/*cache*`, `test/playback/flush_test.dart`,
`test/reader/*save*`, `test/reader/settings_worker_test.dart`, and
`lib/reader/kept_page.dart`. An initial software-design batch also contained a
misspelled `/Users/alexpurslane/...` path; the correct mandatory skill and its
reference were read separately before implementation. Some search-only commands
returned 1 for no match. Attempts to tail completed temporary `.log` files found
no file because the runner had already compressed and removed them. None of
these exploration failures is treated as a successful check.

## Exclusions and follow-ups

No device or browser interaction, live credentials, destructive account action,
external server test, coverage, general mutation campaign, push, pull request,
deployment, peer merge, ticket closure, or worktree removal was performed.
Optional plugin/server tests remain explicit exclusions; the complete full-suite
skip list is archived separately. Native runner diagnostics about missing iOS
SDKs are host warnings, not claims of iOS validation.

The existing acceptance-only DiskCatalog was already incompatible with the
catalog text interface. Its migration ticket td-tswb now records the new
clearCache method. Production and gallery use LocalCatalogStore. New ticket
t5-23yk records existing retained-discovery CPU work and broad recovery catches
that still need engine-rule follow-up. This change does not broaden those catches.

## Reviewed implementation checks

Checks 21 through 27 used the identical reviewed Dart source manifest
`038ef9292e77c1b452d218f78eda8b963a999db9bd9c5eacf8e2079207f01033`.
Check 19 used manifest `fe2bdab9597a` (prefix). Check 20 recorded formatting
input manifest `56554e40720e` (prefix) and changed five files. Their full hashes
are in commands.jsonl. The later analysis, affected suite, full suite and builds
share the reviewed manifest; the earlier focused run and formatting input do
not. This corrects review finding R3.

| Archive label | Outcome |
| --- | --- |
| 19-green-delayed-records | 62 passed; focused delayed preservation and reader record-flush checks |
| 20-format | 28 changed Dart files formatted |
| 21-analyze | All 28 changed Dart files analyzed; no issues |
| 22-affected-final | 777 passed, 3 optional plugin/server tests skipped |
| 23-full-flutter | 3900 passed, 27 skipped, zero failures; concurrency 2 |
| 24-production-js | Release JavaScript build succeeded for lib/main.dart |
| 25-gallery-js | Release JavaScript build succeeded for lib/gallery.dart |

Earlier broad affected check 15 passed 1927 tests with three external skips.
`skips.json` lists all 27 full-suite exclusions: unavailable EPUB fixtures,
opt-in measurements/benchmarks, and three real plugin/server integration tests.
The source's boolean skip conditions supply three reasons that Flutter's
compact output omits. None of these optional checks was claimed as run.

Both web builds emit the CupertinoIcons font-family warning retained in their
logs. They still exit zero. `web-artifacts.json` hashes every emitted file.
Production main.dart.js is 4290880 bytes, SHA-256
`6a0b7a302d0581adb239f104f36e08ff41ea3b97bc94f2d32c422fb963f8fe59`.
Gallery main.dart.js is 2797030 bytes, SHA-256
`f69ad3c2ec1dea570bd1f8a60a79cd8e4b42c8422db17990d48b79742ed8b1e6`.
The build directories are ignored local artifacts; the manifests and logs are
committed. No browser or device validation is claimed.

## Review and fixes

The one independent reviewer assessed implementation commit
`f8565faaf390fe5cf968909f8b8e6d8a764d6483`. Its original report is retained
verbatim in `reviewer-original.md`; launch/completion and original verdicts are
in `reviewer-metadata.json`. All three original assessments were fail. No second
review was requested. `review-resolutions.md` records the lead's fixes and
their evidence without replacing those verdicts.

| Check | Result and resolution |
| --- | --- |
| 28 | Test setup did not compile because its new preferences platform import was missing. The command also used a literal-name filter for alternatives. Added the import and changed to the regular-expression filter. This was not a meaningful red run. |
| 29 | Meaningful red: SQLite live-save failure during upload incorrectly allowed clear to finish; preferences already stopped through its whole-store acknowledgment failure. Both storage modes accepted a new download while covers waited and a new cover while catalog deletion waited. Five failures and one pass. |
| 30 | Both real-player failed-save cases passed after rechecking writers after an exchange. |
| 31 | 83 passed, two fixture failures: the old one-shot synthetic writer completed its signal twice after the new recheck. The fixture now reports its initial save once and permits later no-op flushes. |
| 32 | All 91 focused checks passed, including retry after cache-removal failure and account/credential replacement during final catalog deletion. |
| 33 | Formatted all 28 changed Dart files; seven changed. Its manifest records formatting input. |
| 34 | Analyzed all 28 changed Dart files; no issues. |

One review-fix exploration command searched nonexistent `lib/sync/local*` and
`lib/sync/*store*` paths and returned 2 while still locating the correct methods
in playback/store.dart. No exploration failure counts as verification.

## Final checks after review fixes

After formatting, checks 34 onward use source manifest
`3eedcd2359413f6eeed80f8284c6cb27cde98de99e95a87e63717962e21eef00`.
Check 32's focused run and check 33's formatting input use the earlier manifest
`16043b98177fe91c5be43a8ce6e9394fd2eb0c7deea1a2f33088b62c5c97ec6d`.

| Archive label | Outcome |
| --- | --- |
| 32-green-review-focused | 91 passed |
| 33-format-review-fixes | 28 files formatted; seven changed |
| 34-analyze-review-fixes | 28 files analyzed; no issues |
| 35-affected-review-fixes | 1240 passed, three optional external skips |
| 36-full-flutter-review-fixes | 3912 passed, 27 optional skips, zero failures; concurrency 2 |
| 37-production-js-review-fixes | Release JavaScript build succeeded for lib/main.dart |
| 38-gallery-js-review-fixes | Release JavaScript build succeeded for lib/gallery.dart |

Both release rebuilds retain the CupertinoIcons warning. The new inventory is
`web-artifacts-final.json`; the earlier inventory remains unchanged. Production
main.dart.js is 4291644 bytes, SHA-256
`94358f946bdbce11d99a3fdf042b52c6a4f0cdb2f65cd25b9e0b3c63a4256b69`.
Gallery main.dart.js is 2797030 bytes, SHA-256
`f69ad3c2ec1dea570bd1f8a60a79cd8e4b42c8422db17990d48b79742ed8b1e6`.

`skips-final.json` lists the final run's 27 skips and was compared with the
earlier inventory: they are identical. `verification.json` records successful
hash verification of all 38 archived command logs, their compressed files and
available source manifests. The original review is preserved byte-for-byte
with SHA-256 `0b02c56f75da31ba7bb75d898103e97bd515d72a2688f2a2655a43f1775d1f3a`.

The lead considers R1, R2 and R3 resolved with the evidence in
`review-resolutions.md`. The original review verdicts remain fail. All owned
build/test commands and the one reviewer are finished. Integration, device
acceptance, the combined boo-39cu behavior and hardening remain with the parent.
The final commit's complete base-to-HEAD diff/clean-state check is archived at
`.cache/boo-xyrl-final-verification.json`, outside tracked evidence so recording
the final HEAD does not itself change that HEAD.
