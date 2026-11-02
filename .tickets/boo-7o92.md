---
id: boo-7o92
status: in_progress
deps: [boo-u3cg]
links: []
created: 2026-11-01T21:37:34Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Implement verified downloads and media network policy

One policy governs streaming, audio downloads, ebook downloads, and reader assets. Prefer local files, block automatic transfers off Wi-Fi, and handle network handover.

## Design

docs/plans/bookfin.md

## Acceptance Criteria

Red-green tests cover Wi-Fi loss, unknown network, partial files, missing files, interruption, retry, cancellation, free space, and separate audio/ebook status. Test on Android.


## Notes

**2026-11-02T04:25:17Z**

Implementation from 204fa5b complete for parent integration; leave in_progress. One durable account/source-revision owner, shared local-first media policy, native Android network/free-space/private-storage boundary, safe verified range resume, separate audio/ebook status, Downloads navigation and retry/cancel/remove, and player localFile lookup. Meaningful red-green failures include wrong authenticated user, source replacement during bytes, stale account request, failed manifest writes, immediate cancel/retry, old-revision removal, missing-file byte counts, and lookup during restoration. Final: 144 tests (34 new), SDK-link checks, zero-change format check, clean analyzer, Android debug APK and JavaScript web release all pass through Nix, sequentially. Android synthetic loopback fixture confirmed Wi-Fi pause at 393216 bytes, matching Range resume, process restart, 1/2 to 2/2 files, independent private-file SHA-256, denial/retry, Cancel, removal, ebook-only listening-filter exclusion, and sign-out. Final APK reinstalled; Wi-Fi/mobile restored; fixture/forward removed; own device session released without shutdown; app signed out. No secrets, real-server requests, preview changes, coverage/mutation, child agents, or PR. docs/downloads.md records exact proof, API and limitations. Follow-ups t9-04iu (alternate-source safe original route), t9-k4lf (retained storage outside catalog); real-server acceptance stays boo-2cgp.


## Parent review corrections

The parent reproduced all four static review findings with five meaningful failing tests: replacement-response interruption retained three old bytes under the new validator; cancellation waited for unrelated media; immediate cancel and remove missed restored requests; and an early file denial hid the active state of later files.

Replacement responses now discard the prior prefix before saving the new validator. The regression restarts the download owner and checks the resulting replacement bytes. Cancellation saves disabled requests before waiting for only the affected active transfer to close. All serialized commands wait for account restoration and recheck account generation before execution. Queued work takes display precedence over a file error, preserving Cancel while keeping the error message.

Parent verification: 149 application tests pass, analysis has no issues, and the changed Dart files are formatted through the pinned Nix shell. The five new tests failed before implementation; the existing 144 tests remain green. Logs: /tmp/bookfin-download-fixes-red.log, /tmp/bookfin-download-fixes-suite.log, /tmp/bookfin-download-fixes-analyze.log. These corrections have not yet been inspected on Android; earlier Android observations describe the builder head. Independent correction review and integration remain pending. No coverage or mutation jobs ran.
