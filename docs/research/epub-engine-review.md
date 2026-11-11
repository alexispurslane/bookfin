# EPUB engine comparison review and resolution

Exactly one fresh read-only review ran with provider `codex`, model `gpt-6.1-sol`, and `reasoningEffort: xhigh`. It inspected the complete original-base `6ba37d9a4a23be07f857d369da73115fedcc53fb` through built/evidence HEAD `9f51a8fb401368d38ded1345bef2a5cbf975a12e` diff. The reviewer ran no builds, tests, Nix commands, or device actions.

## Original reviewer report

The following report preserves the original verdicts and finding. The resolution follows it; it does not replace the review with a new pass verdict.

Overall verdict: changes required. The retained measurements reconcile; one reference-publication defect needs a small fix. It does not invalidate the completed benchmark.

Reviewed base `6ba37d9a4a23be07f857d369da73115fedcc53fb` through HEAD `9f51a8fb401368d38ded1345bef2a5cbf975a12e` on `t3/measure-epub-engines`. The checkout was clean before and after review.

| Assessment | Verdict |
| --- | --- |
| Correctness | changes required |
| Ticket fulfillment | changes required |
| Design | pass |

### Correctness: changes required

C1 · P2, normal-priority defect · Failed reference promotion overwrites its output.

Location: `tool/research/epub_engines/calibrate.py:90`

```python
    args.output.write_text(json.dumps(references, indent=2) + "\n")
    if failures:
        print("\n".join(failures))
        if not args.draft:
            raise RuntimeError("Reference promotion refused; inspect and resolve calibration evidence")
```

where

- `args.output.write_text(...)` replaces the requested output file.
- `references` contains the candidate page-reference records; `json.dumps(...)` converts them to JSON text.
- `failures` contains the failed validation checks.
- `print("\n".join(failures))` reports those failures on separate lines.
- `args.draft` permits unapproved draft output.
- `RuntimeError(...)` ends a non-draft promotion with an error.

Trigger: run a non-draft promotion with failed OCR or missing illustration approval, using an existing accepted reference file as the output.

Expected: reject the promotion and leave the accepted file unchanged.

Actual, established statically: the candidate file replaces the accepted file before rejection. This changes the frozen reference digest and prevents subsequent collection against the previous measurements. The collector rejects mismatched or unapproved references rather than silently accepting them, so this is evidence preservation and repeatability damage—not evidence that the current timings are wrong.

Remedy: reject failed non-draft candidates before publishing the output. Add behavior tests proving that rejection neither replaces an existing file nor creates an approved output. Explicit draft output can retain its present behavior. This reproduction was not executed.

### Ticket fulfillment: changes required

The measurement requirements are met by the inspected evidence. C1 is the remaining proportionate, in-scope repair before accepting the reusable harness.

| Requirement | Evidence and review result |
| --- | --- |
| Three real release engines on one emulator | Build configuration, retained APKs, and all recorded runner commands agree. Bookfin imports production loader/pager/viewport/cache code; KOReader loads the official `cre` library, not unrelated CoolReader. |
| Pinned public inputs and settings | Independently recomputed all six APK hashes. All three target APKs contain matching EPUB bytes, the shared font, and the recorded fixture manifest. KOReader library hashes also agree. |
| Actual opens, reopens, turns, crossings, and font changes | The shared 23-step workload and AndroidJUnitRunner assertions exercise those operations. Every measured job has its complete records, completion marker, and successful assertion log. |
| Independent content and completion evidence | All 63 reference PNG pixel hashes and PNG-file hashes agree with the frozen references. Inspected all nine seven-case contact sheets and representative full-size measured PNGs. The evidence supports the tested destinations and rejects blank, stale, and wrong-reference frames. |
| Repetition and statistics | Independently confirmed 108 distinct process starts, 12 balanced rounds, 1,404 measured rows, and 1,080 preparation rows. Every engine/book pair has 12 fresh opens and 36 samples for each other operation. All 45 count/median/p90 cells and all nine startup summaries reconcile. |

The frozen manifest’s SHA-256 matches the supplied `6d6afee5…4710b2` value and every collected row. No numerical-claim mismatch was found.

Fixing C1 alone does not require repeating the measurements, provided the accepted reference bytes and engine/timing implementation remain unchanged. Parent integration, homepage work, and ticket closure remain outside this review.

### Design: pass

The implementation follows the User/Ousterhout ownership model and Muratori’s reuse rule: it reuses production Bookfin rendering instead of adding another renderer. The shared workload owns operation order; engine adapters retain their engine-specific navigation; shared capture code owns window-copy evidence.

The shared components hide real decisions rather than merely forwarding calls. No separate material ownership, information-leakage, or unnecessary-abstraction finding emerged. C1 is a failure-ordering defect inside the existing publication owner; it does not justify a new framework.

### Validation and comparability limits

- I read retained logs and performed permitted arithmetic, hash checks, and image inspection. I ran no builds, tests, Nix commands, or device operations.
- Retained final logs report 34 harness tests, scoped application analysis, shell analysis, formatting, and native checks passing; Flutter reports 2,649 passed and 21 skipped. These were not rerun. The earlier unscoped analyzer failure remains disclosed.
- The timing boundary ends at a matching Android window copy, not physical display presentation or pure engine computation. Instrumentation, polling, Flutter texture composition, and capture work remain measurement costs.
- Whole-book pagination work differs between engines. Chapter crossings are warm; page boundaries, illustration sizes, and font-change work differ. Variable host load limits precision. The results support no universal winner, physical-phone prediction, or equal-rendering-quality claim.
- Coverage, mutation testing, and repair of gesture-input ticket boo-kdc6 remain unverified and are not claimed here.

Overall: changes required for C1; the completed benchmark evidence otherwise passes this review.

## Ticket lead resolution

C1 is resolved. Two behavior tests reproduced the defect before the fix. One proved that failed OCR replaced an existing accepted reference. The other proved that missing image approval created a rejected output file. Both failed at their output-preservation assertions, not at imports or setup. Evidence: `tool/research/epub_engines/evidence/review-c1-red.txt`.

The single reference publisher now rejects a failed non-draft candidate before writing its output. No new state owner or publication path was added. Explicit drafts still retain unapproved evidence for inspection. The seven calibration tests pass, including both reproductions, successful publication, required workload assertions, and explicit draft behavior. All 37 host harness tests pass. Evidence: `review-c1-green.txt` and `review-c1-host-tests.txt` in the same evidence directory.

The accepted manifest, all raw samples, summarized metrics, engine code, and timing code remain byte-for-byte unchanged from the reviewed HEAD. The accepted manifest SHA-256 remains `6d6afee5742aff09b2c08b7dd510b1f922343162adb59776bdda3c426d4710b2`. The fix changes only the host calibration publisher and its tests. It therefore needs no new device measurements. Unchanged-evidence checks are in `review-c1-integrity.txt`.

No finding remains unresolved. There was no second review and no review-verdict substitution. The project checks recorded before review remain applicable to unchanged application and shell code. The original root-wide analyzer failure remains disclosed. Parent integration and ticket closure remain pending.
