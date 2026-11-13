(•̀_•́) Overall verdict: fail — changes required before integration.

Reviewed the complete original-base-to-HEAD diff from `2f5f0393d4d5961627b7eb84f7c2f7725ab762aa` to `f8565faaf390fe5cf968909f8b8e6d8a764d6483` on `t3/clear-account-data`. The checkout was clean. No files were changed and no builds, tests, analysis, devices, browsers, or children were started.

| Assessment | Verdict | Evidence and gaps |
|---|---|---|
| Correctness | Fail | Account binding, durable acknowledgments, file holds, refresh retirement, and scoped deletion have substantial source and retained-test evidence. R1 and R2 leave concrete ordering gaps. Their reproductions below are static predictions, not executed experiments. |
| Ticket fulfillment | Fail | Current-account glass confirmation, record retention, other-account isolation, login/appearance retention, and public Downloads removal are implemented. R1 violates required preservation before removal; R2 permits a successful clear with recreated files. |
| Software design | Fail | Existing owners, narrow subscriptions, and the reader’s separate record flush are appropriate. R2 exposes an ownership defect: each storage owner ends its clearing protection before the screen’s whole operation ends. No separate playing-audio removal mechanism was added. |

R1 — P1: A live-record save failure during upload can still authorize removal.

Source: [coordinator.dart:350](/Users/alexispurslane/.t3/worktrees/bookfin/t3-5d89a0e3/lib/sync/coordinator.dart:350).

```dart
      await records.flushWriters(account: confirmed.scope.key);
      guard();
      while (await records.hasPendingUploads(confirmed.scope.key)) {
...
        await transport.synchronize(confirmed, client);
        guard();
      }
      guard();
      completed = true;
```

where

- `records` owns durable personal records; `flushWriters` asks registered live writers to save.
- `confirmed.scope.key` identifies the confirmed account; `hasPendingUploads` checks only its durable actions awaiting server acknowledgment.
- `transport.synchronize` exchanges records through `client`, the Jellyfin client.
- `guard` checks operation/account validity; `completed` records successful completion.

The live writers report failed saves through their registration callbacks: [playback.dart:289](/Users/alexispurslane/.t3/worktrees/bookfin/t3-5d89a0e3/lib/playback/playback.dart:289) and [session.dart:251](/Users/alexispurslane/.t3/worktrees/bookfin/t3-5d89a0e3/lib/reader/session.dart:251). Those callbacks are not checked again after an upload.

Unexecuted reproduction:

1. Let initial preservation finish, then create a pending record while a download remains held.
2. Release the hold and pause the upload started by `beforeRemoval`.
3. Make another live bookmark change whose local save fails, then acknowledge the earlier durable actions.

The durable pending set can now be empty while the writer still holds an unsaved change. The required upload returns successfully, allowing file deletion and eventual success reporting.

Impact: the required-save safeguard can be bypassed. This establishes premature removal and false success, not observed loss of already-durable history.

Fix direction: revalidate live-writer preservation after each awaited exchange before authorizing removal, repeating upload when that save produces pending actions. Add a real-writer failure test during the final removal callback’s upload. Existing tests cover durable changes during upload and failures before upload, but not this interval.

R2 — P2: Storage protection ends before the whole clear finishes.

Source: [clear_data.dart:39](/Users/alexispurslane/.t3/worktrees/bookfin/t3-5d89a0e3/lib/settings/clear_data.dart:39).

```dart
    await preserveRecords();
    await downloads.clearAccount(confirmed, beforeRemoval: preserveRecords);
    guard();
    await covers?.clear(confirmed.scope);
    guard();
```

where

- `preserveRecords` performs the required account-bound save/upload.
- `downloads.clearAccount` removes downloads; `covers.clear` removes account cover files.
- `confirmed` is the confirmed session; `guard` rejects a superseded catalog operation.

Downloads releases its protection in [local_downloads.dart:838](/Users/alexispurslane/.t3/worktrees/bookfin/t3-5d89a0e3/lib/downloads/local_downloads.dart:838):

```dart
    } finally {
      if (_clearing == clearing) _clearing = null;
    }
```

where `_clearing` is Downloads’ active bulk-clear ownership and `clearing` identifies this invocation.

Covers likewise releases its protection when its own deletion ends, at [covers_io.dart:189](/Users/alexispurslane/.t3/worktrees/bookfin/t3-5d89a0e3/lib/catalog/covers_io.dart:189). The catalog remains visible until its later cache deletion completes at [controller.dart:1376](/Users/alexispurslane/.t3/worktrees/bookfin/t3-5d89a0e3/lib/catalog/controller.dart:1376).

Two reachable, unexecuted reproductions:

- Hold an existing cover fetch so cover clearing waits. After download clearing finishes, request a download through the still-visible library. Downloads accepts it because its protection has ended. Let that download complete, then release the cover fetch: the overall clear can succeed with downloaded files remaining.
- Hold final catalog-cache deletion after cover clearing. Cause a still-visible book thumbnail to request an uncached cover. Covers accepts and saves it; catalog deletion then finishes without another cover removal.

Impact: “Local data cleared” can describe an operation that left recreated downloads or covers.

Fix direction: keep account-scoped storage protection active through the existing whole-clear operation, including final catalog publication. Cover callers using the retiring catalog must not recreate its files during that interval. Add controlled tests spanning these phase boundaries.

Design basis: User’s single-owner/state-transition rules and Ousterhout’s information hiding. The shared invariant—cleared storage stays clear until completion—is currently split across three different lifetimes. Adding or delaying a phase requires callers to understand and coordinate all three. This is a concrete ownership defect independent of runtime reproduction.

R3 — P3, nonblocking: The evidence README overstates source-manifest identity.

[README.md:120](/Users/alexispurslane/.t3/worktrees/bookfin/t3-5d89a0e3/docs/evidence/boo-xyrl/README.md:120) says all listed final commands used the same Dart manifest. The archived command records instead show:

| Check | Manifest prefix |
|---|---|
| 19, focused tests | `fe2bdab9597a` |
| 20, formatting input | `56554e40720e` |
| 21 onward | `038ef9292e77` |

Check 20 reports formatting five files. Correct the README to distinguish the earlier focused run and formatting input from the final source. This does not invalidate the later full-suite evidence.

Retained evidence verified:

- All 27 compressed logs and their decompressed contents match the recorded hashes; archived source-manifest hashes also match.
- The current Dart sources match final manifest `038ef9292e77c1b452d218f78eda8b963a999db9bd9c5eacf8e2079207f01033`.
- Logs report check 19: 62 passed; check 22: 777 passed/3 skipped; check 23: 3900 passed/27 skipped; final analysis clean.
- Production and gallery release JavaScript builds succeeded. Both retained artifact inventories match the files on disk. The CupertinoIcons warning remains documented.
- Inspected failed-save and delayed-preservation red logs show behavioral failures, and the later logs show passing runs.

The boo-39cu boundary is structurally appropriate: this branch awaits public removal and repeats preservation after existing file holds. Its actual playing-audiobook behavior remains a parent integration check; absence of the peer implementation is not a defect in this branch.

Remaining limits: R1/R2 were not executed; combined boo-39cu behavior, device acceptance, external plugin/server checks, coverage, and mutation testing remain unverified. The recorded pre-existing follow-ups are not counted as new findings. R1 and R2 block readiness.