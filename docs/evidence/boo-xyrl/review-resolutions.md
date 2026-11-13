# Review resolutions for boo-xyrl

The original review of f8565faaf390fe5cf968909f8b8e6d8a764d6483 remains in
reviewer-original.md. Its correctness, fulfillment and design verdicts were
all fail. These are the implementation lead's resolutions, not a new review.
No second reviewer or review run was started.

## R1 — required live save during an upload

Accepted and fixed. RecordSync rechecks registered writers after every awaited
exchange, before the durable pending set can authorize removal. Any resulting
new durable actions are uploaded by the existing loop. Writer errors continue
to propagate; the Settings controller handles expected Exceptions only.

The reproduction uses a real Playback writer, real LocalResumeStore, a real
download held through its public read boundary, and controlled transport. It
creates another durable record during the hold, then fails a live bookmark
save during the final removal callback's held upload. The SQLite trigger
rejects the insert while allowing acknowledgment of the earlier actions.
Check 29 showed premature success in SQLite. Preferences already stopped
because its whole-store acknowledgment also failed; that case remains tested.
Check 30 passed both cases after the fix, including restoring storage and
retrying, which saves/uploads the retained live bookmark before deletion.
Check 32 passed the complete focused set of 91 tests.

## R2 — one lifetime through catalog publication

Accepted and fixed. The catalog controller still owns the one clear operation.
Its guarded clearCache continuation removes the saved catalog and publishes
the empty library while the file owners remain protected. Downloads and Covers
have narrow afterRemoval continuations, awaited before their existing clear
ownership is released. Thus a delay in a later phase cannot reopen writes in an
earlier phase. There is no separate operation state machine or playback-removal
mechanism. Exceptions release each owner's protection through its existing
finally/whenComplete path.

Check 29 reproduced both lifetime gaps in preferences and SQLite: a download
request succeeded while an old cover fetch held cover removal, and a cover
request returned saved bytes while final cache removal was held. The same tests
pass in check 32. That run also verifies new requests remain blocked during
final cache deletion, cached and blurred cover requests return no image, the
catalog is empty on completion, account/credential replacement during final
cache deletion fails the operation without touching another account, and a
cache-deletion failure releases protection so the user can retry.

The parent must preserve these continuations and the existing awaited public
remove/removeRetained boundary when integrating boo-39cu. The peer branch's
actual pause/book-switch behavior remains an integration check.

## R3 — source manifests in the evidence summary

Accepted and corrected. README now distinguishes the earlier focused run and
formatting input from the identical manifests used by checks 21 through 27.
No original command record, log, source manifest, or review text was changed.

## Remaining limits

The reviewer did not execute R1/R2. The implementation lead subsequently ran
their reproductions and fixes as recorded above. Device acceptance, external
plugin/server tests, combined boo-39cu playback behavior, coverage and mutation
testing remain parent-owned exclusions. Final affected/full-suite/build checks
and final HEAD details are recorded in README and commands.jsonl.

Final validation after the fixes: 1240 affected tests passed with three optional
external skips; the full suite passed 3912 tests with 27 unchanged skips; all
28 changed Dart files analyze cleanly; both release JavaScript entrypoints
build. Checks 34 through 38 share source manifest
`3eedcd2359413f6eeed80f8284c6cb27cde98de99e95a87e63717962e21eef00`.
No material review finding remains unresolved. The original failing verdicts
are preserved rather than relabeled as independent approval of the fixes.
