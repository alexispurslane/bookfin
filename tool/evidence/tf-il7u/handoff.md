# tf-il7u: idle-layout frame test investigation

## Checkout and scope

- Worktree: `/Users/alexispurslane/.t3/worktrees/bookfin/t3-db20027d`.
- Branch: `t3/fix-idle-layout-frame-flake`.
- Original base and initial HEAD: `403b803d24b5e20a9a249ca094dff477fba90eac`.
- Initial status: clean. No inherited uncommitted edits or commits above the base.
- The base includes boo-hwoz collection changes. They remain unchanged.
- Ticket: `.tickets/tf-il7u.md`, already in progress, with no dependencies.
- Production files, fixture sizes, layout budgets and existing time limits remain unchanged.
- Parent owns integration, acceptance, hardening and ticket closure. No product fork arose.

## Cause and controlled evidence

The old test treated a completed deep-page request as evidence that idle layout
ran while a frame was pending. That inference is false. A pending frame is a
frame for which Flutter's `hasScheduledFrame` flag is true at callback execution.

`Redraws.build` registers its next redraw request as a post-frame callback.
The scheduler can register its waiting idle callback before that request.
At the next frame's end, Flutter runs the idle callback first, with no next
frame pending. The redraw callback then requests the next frame. One legal
idle step can therefore run per frame. The page can finish within ten frames
when each layout step gets through enough text within its unchanged budget.

The preparation-before-first-frame hypothesis was not confirmed. The observed
real PageSource trace has this order:

1. Section preparation completes with no frame pending and no layout callback.
2. The test requests the deep page with no frame pending.
3. Its first layout step is scheduled with a frame already pending.
4. The first Redraws frame ends and requests another frame, without an idle step.
5. Each later frame admits one idle callback before its redraw callback.

`02-original-order-trace.log.gz` records every observed callback and scheduler
phase. That diagnostic run passed the old test, so it is ordering evidence,
not a reproduction of the completion failure. Instrumentation can affect how
much text fits in a step. The unchanged run in `01-original-frames.log.gz`
failed the original assertion with four passes and one failure.

The controlled experiment removes layout speed from the question. It queues
exactly three callbacks through the real production scheduler and uses the
original Redraws widget. Each of three frames executes exactly one callback
with no frame pending. A frame is pending again after each pump. The old
completion assertion then fails: expected false, actual true. There are no
sleeps, bigger fixtures or changed layout budgets. See
`03-controlled-original-oracle-red.log.gz` and its saved diagnostic patch.

The permanent regression tests cover both post-frame callback orders:

- If the redraw callback requests the next frame first, idle work stays held
  for ten frames, causes no busy task polling, then executes once after release.
- If the idle callback precedes the redraw request, exactly three callbacks
  finish in three frames, with none executing while a frame is pending.
- The original real PageSource test observes actual callbacks. It checks at
  most one idle callback per frame and zero callbacks while a frame is pending
  or frames are disabled. It still requires page completion after removing
  Redraws. Completion before removal is also legal.

The existing animation and background tests now also assert zero idle
callbacks during their holds. Their request-completion assertions remain.
The urgent animation case still proves that urgent work completes.

`LayoutSteps` is a test-only observer. It delegates to
`PageSource.scheduleBetweenFrames` and calls the real layout callback. It
neither decides admission nor changes priority, callback order or step budget.
The existing PageSource injection point is sufficient. No production test hook
or alternate scheduler is added. The bug class is a test inferring protected
interval execution from eventual completion. Actual callback counts replace
that inference in the affected frame tests.

The production caller remains `EpubPager` in `lib/reader/epub/pager.dart`.
PageSource still owns preparation, request ordering, cancellation, settings,
eviction, excerpts and urgent layout. The observer uses its existing schedule
argument. Related reader and crossing tests exercise those paths.

## Negative control

Temporarily remove only `binding.hasScheduledFrame` from the production
`held()` condition, leaving its background and urgent decisions intact.
The corrected seven-test suite then has two passes and five failures.
In particular, the original real PageSource test observes eleven callbacks
where at most one is allowed per frame. The controlled pending-frame test
observes one callback where zero is required. The controlled three-step test
observes three callbacks where one is required. These failures test behavior,
not syntax or missing symbols.

`06-negative-control.patch.gz` records the deliberate violation.
`06-negative-control.log.gz` keeps the entire failing run. Restore the exact
original production file before further tests. The production diff is empty.
This single control is bug investigation, not a general mutation campaign.

## Verification commands and results

All commands run in the worktree above through its pinned Nix development
shell. Flutter uses at most two test workers. One heavy command runs at a time.
Complete stdout and stderr are retained, including all failing runs.
The `.gz` files preserve original bytes. Read them with `gzip -dc <path>`.
`logs.tsv` records original paths, byte counts and SHA-256 hashes of those bytes.
Compression keeps existing whitespace in logs and experimental patches without
adding whitespace errors to the source diff.

| Evidence | Command or change | Result |
| --- | --- | --- |
| 01-original-frames | `nix develop --command flutter test --concurrency=2 --reporter=expanded test/reader/epub/page_source_frames_test.dart` on original files | Exit 1; 4 passed, original idle-layout assertion failed |
| 02-original-order-trace | `nix develop --command flutter test --concurrency=2 --reporter=expanded test/reader/epub/page_source_frames_test.dart --plain-name 'idle layout gives way'` with diagnostic observer | Exit 0; 1 passed; trace records actual callback order |
| 03-controlled-original-oracle-red | `nix develop --command flutter test --concurrency=2 --reporter=expanded test/reader/epub/page_source_frames_test.dart --plain-name 'controlled original redraw ordering'` with saved diagnostic patch | Exit 1; completion assertion rejects three legal callbacks |
| 04-corrected-frames | `nix develop --command flutter test --concurrency=2 --reporter=expanded test/reader/epub/page_source_frames_test.dart` after observer and late-redraw regression | Exit 0; 6 passed |
| 05-corrected-order-cases | `nix develop --command bash -c 'dart format test/reader/epub/page_source_frames_test.dart && flutter test --concurrency=2 --reporter=expanded test/reader/epub/page_source_frames_test.dart'` | Exit 0; 7 passed |
| 06-negative-control | `nix develop --command flutter test --concurrency=2 --reporter=expanded test/reader/epub/page_source_frames_test.dart` with the saved temporary production violation | Exit 1; 2 passed, 5 failed as described above |
| 07-repeat-1 through 07-repeat-5 | Five sequential frame commands after restoring production | Each exit 0; 35 test passes in total |
| 08-reader-crossings | `nix develop --command flutter test --concurrency=2 --reporter=expanded test/reader test/crossings` | Exit 0; 1,714 passed, 21 skipped |
| 09-full | `nix develop --command flutter test --concurrency=2 --reporter=expanded` | Exit 0; 3,676 passed, 27 skipped |
| 10-analysis | `nix develop --command flutter analyze --no-pub lib/reader/epub test/reader/epub` | Exit 0; no issues |
| 11-format-diff | `nix develop --command bash -c 'dart format --output=none --set-exit-if-changed test/reader/epub/page_source_frames_test.dart && git diff --check 403b803d24b5e20a9a249ca094dff477fba90eac && git diff --exit-code 403b803d24b5e20a9a249ca094dff477fba90eac -- lib'` | Exit 0; no format changes, whitespace errors or production diff |

The repeat command is exactly:

```sh
nix develop --command bash -c 'for run in 1 2 3 4 5; do flutter test --concurrency=2 --reporter=expanded test/reader/epub/page_source_frames_test.dart > "/tmp/bookfin-tf-il7u/07-repeat-${run}.log" 2>&1; result=$?; printf "run %s exit %s\n" "$run" "$result"; if [ "$result" -ne 0 ]; then exit "$result"; fi; done'
```

Five fresh test processes provide bounded repeat evidence for this intermittent
failure. These passes are not the cause proof. Cause proof is the observed
order and controlled failing completion assertion. Regression proof includes
the deliberately broken scheduling contract.

The reader suite skips opt-in benchmarks and corpus checks, plus unavailable
trial books. The full suite retains those skips and additional opt-in measurements
and optional server integration checks. Exact test names and skip
reasons remain in the full logs. No test was disabled for this change.

## Original parent evidence

The ticket retains the boo-hjal failure and passing rerun references. It also
retains boo-hwoz's full-suite failure and two frame-suite failures, including
one without its collection production change. None of those retries diagnosed
the failure. The original boo-hwoz logs remain at `/tmp/bookfin-boo-hwoz/`.
Their complete copies are retained as `parent-hwoz-*.log.gz`:

| Log | SHA-256 |
| --- | --- |
| full-suite.log | `7e095499984513598b6f283137f5ec7e828d157db1991e7a5bf616a1921ff8ac` |
| frames-repeat.log | `0c7579ea59ed3ebad29a219de42d6634481460d23c2f119bbc9d5204c34e08f4` |
| frames-original-production.log | `0c7579ea59ed3ebad29a219de42d6634481460d23c2f119bbc9d5204c34e08f4` |

## Limits and ownership

- No device or browser acceptance, live accounts, build/deployment, push, PR,
  merge, coverage or general mutation campaign. t1-dth0 and t7-3j9c remain
  existing device/browser blockers, with no retry or bypass.
- t5-rplx remains an unexplained record-recovery failure outside this scope.
- No collection changes or D1 CPU work. Those belong to boo-hwoz and t9-ftlz.
- No process was stopped, by name or by ID. No owned command was interrupted.
- Nix logs retain existing SDK discovery warnings. Host Flutter tests do not
  establish Android or browser behavior.
- Timing repeat evidence cannot prove absence of every future flaky test.
  The replacement assertions depend on work and frame counts, not host speed.
- Historic failures did not record callback order. The trace and controlled
  experiment establish the invalid completion inference, without claiming to
  reconstruct every historical run.

## Review

One fresh read-only Astra high reviewer is required after implementation and
all required checks. Its original separate verdicts, evidence, gaps and link
will be retained here with any direct fixes. No second review is authorized.
