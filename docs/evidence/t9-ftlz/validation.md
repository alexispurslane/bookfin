# t9-ftlz implementation evidence

## Identity and scope

Initial checkout: `/Users/alexispurslane/.t3/worktrees/bookfin/t3-c3dea442`,
branch `t3/offload-collection-processing`, clean HEAD
`0f1b55762aef7ea17c2460242203cd972d767014`. No checkout was created,
reset, switched or removed. The ticket was already in progress and stays so.
The parent owns integration, acceptance, hardening and closure.

Read AGENTS.md (no checkout CLAUDE.md exists), docs/plans/bookfin.md,
the full ticket, builder.md, software-design, test-driven-development and its
writing-good-tests reference, and ultracode-orchestration. `tk ready` and
`tk dep tree t9-ftlz` confirmed the closed prerequisite boo-hwoz.

The production caller is CatalogController._refresh. It awaits client.catalog
before its own worker. That later worker therefore cannot cover collection
processing. Its retention policy belongs to boo-8xyn and is unchanged here.
The existing JsonTransport.fetchBody and foundation/IsolateHop interfaces
already support this work; neither transport nor controller needs a change.

## Processing and ownership

JellyfinClient remains the one request-local owner. Its network operations and
credential rejection remain on the caller's isolate. Each collection response
crosses as a byte array plus start/count scalars into the existing native
compute mechanism. The page worker decodes JSON, validates count, start and
item IDs, rejects within-page duplicates and returns only IDs and optional
names. Page maps return without a native result copy through Isolate.exit.

The client stores pages and reads only their count scalar. One discovery
worker validates complete listings, checks duplicates across pages, checks
names and density, merges shared collection IDs and returns the request list.
The client drops the discovery pages, then fetches direct children in the
existing batches of eight. One final worker validates cross-page uniqueness
and builds the item-to-series map from the compact child pages. That map goes
through the unchanged CatalogPages interface to the existing catalog worker.

There is no per-item hop and no repeatedly transferred growing accumulator.
There is one page hop per HTTP page, plus discovery and membership reductions
when collections exist. The full compact pages cross into their reduction
once. This still requires native input graph copies and request-local memory;
there is no latency, UI-frame-budget or total-heap improvement claim. All
compact child pages remain until the final reduction. No retained cache,
long-lived worker, generic worker framework or controller map was introduced.
No product choice or freshness policy changed. Every refresh fetches again.

The client guards credentials and closure before and after each worker await.
Closing still aborts network activity. An already running compute call may
finish; its result is rejected and no later request is started. Workers never
receive a session, credential, client, transport, network handle or controller.
Optional malformed metadata still gives an empty collection map. Dart Errors,
including StateError and AssertionError, propagate instead of being treated as
ordinary optional metadata failures.

Browser compute executes on the browser event loop and does not create native
isolation. Browser behavior is preserved by using Flutter's same compute API,
but browser execution is outside this task and was not tested.

## Behavioral evidence

Before implementation, the only production change was a constructor injection
seam, saved exactly in red-seam.json. The old collection processing still ran
unchanged. The first red run observed six decoded collection sends rather than
zero and swallowed a StateError. The second red run made the missing boundary
explicit: expected eight worker calls, observed zero; StateError was still
swallowed. Both runs compiled and failed behavioral assertions. Neither
failure was a fixture or compilation failure.

The worker test runs each production callback with Isolate.run and compares
its control port with the originating isolate. Page maps are guarded so that
traversing their keys or reading their values on the UI isolate throws. The
real discovery and membership reducers must therefore traverse them in a
worker. The test records actual transferred inputs and results. For two
libraries sharing one collection with 601 children it observes:

- Six response byte arrays sent to six page workers, each exactly once.
- Two discovery records reduced to one collection, so child reads occur once.
- Four child pages at source starts 0, 200, 400 and 600.
- One membership reduction producing 601 correct item-to-series entries.
- Eight worker invocations total, all off the originating isolate.

These counts describe this controlled fixture, not latency or heap use. The
test's audit returns an extra copy of the input solely for observation; that
extra audit transfer is not part of production.

Native worker gates test closure during page parsing, discovery reduction and
membership reduction; credential rejection during membership reduction; and
an old account's pending worker alongside a new account. Errors thrown inside
a native worker remain Errors. Malformed JSON, nonobject roots, nonobject items
and invalid discovery names retain optional fallback.

The unchanged source-backed loopback fixtures in collection_queries_test.dart
still cover both Jellyfin paging orders, sparse/empty pages before later books,
direct membership, shared IDs, >1000 collections, >4000 source children,
malformed metadata, cancellation, no shown libraries and every-refresh changes.
They model immutable source behavior, not a live Jellyfin server. Source
provenance remains in docs/evidence/boo-hwoz; no new live compatibility claim is
made.

## Validation record

Exact commands, start/end times, exit statuses, raw log paths and SHA-256 hashes
are in commands.json. Structured suite results preserve each failed and skipped
test. No command is considered passed merely because a later run passed.
Host Flutter commands report missing iphoneos/iphonesimulator SDKs. No iOS
execution is claimed. There was no device/browser check, live server access,
credential request, coverage/mutation campaign or timing-threshold change.

The controller-level account replacement test additionally holds Alice's
membership reduction in a native isolate, signs out, signs in as Bob, and
finishes Bob's refresh before releasing Alice's worker. It verifies Bob's
shown series and exact saved catalog remain unchanged after Alice completes,
and that Alice's cancelled request writes no catalog.

The focused suite passed 145 tests. The affected catalog/settings/app/downloads/
playback/sync suite passed 1,679 tests, with three existing plugin integration
skips. The controller-level account replacement test was added after that run
loaded the worker-test file; its focused follow-up and the full suite cover it.

The first full run completed with 3,688 passed, 27 skipped and one failure:
`idle layout gives way to each frame that is scheduled, and goes on once no
frame is scheduled`, at page_source_frames_test.dart:188. The assertion was
`idle steps ran in a row between frames`, expected false, got true. The exact
failure events and equal original-base/current hashes of the frame test and
page_source.dart are in idle-frame-failure.json. This is a recurrence of tf-il7u.
The parent supplied prior original-production reproduction evidence. No new
cause is inferred, and this collection change does not claim to fix it.

A subsequent controlled red test held a native worker before it threw an
IsolateSpawnException, closed the client, then released the worker. It received
a successful CatalogPages result instead of cancellation. The optional
exception handler is now one path for CatalogFailure and other Exceptions,
with closure checked first. Dart Errors do not enter that handler. The
red-cancel-failure log preserves the original meaningful failure. This change
justifies the final affected/full reruns; the earlier full run stays recorded.

After the cancellation correction, the 39 focused collection tests passed.
The final affected suites passed 1,681 tests, with the same three explicit
plugin-integration skips and no failures. Both account-replacement tests and
the worker-infrastructure cancellation test are included in that final run.

Parent coordination update received while the final full run was underway:
tf-il7u has a reviewed, test-only correction integrated on main as
`2a9df513d398ba86f0a6142abe1c7240e43e570e`, with evidence commit
`96eb86b5726891b9d6a89e24c72536d3cfbe1109`. The parent reports that completion
during Redraws can be legal when an idle callback runs before the next frame
request; corrected tests measure callback counts and pending-frame state.
Production is unchanged. The parent reports 3,676 passes and 27 skips for that
work. Those are parent results, not a test of this collection worktree.

This worktree deliberately retains the original-base frame assertion. No
frame-test change was edited or cherry-picked here. A recurrence in the final
run is retained with reference to the integrated correction, not retried toward
a passing result or diagnosed again. The final rerun was already justified by
the collection cancellation correction and started before this parent update.
The parent will verify the combined changes at integration. t5-rplx remains
separate and unexplained.

The final full suite completed with 3,689 passed, 27 skipped and exactly the
same old tf-il7u assertion failure. full-suite-final.json preserves the final
failure, printed stack and every skipped test/reason. All test processes
finished; no test run was interrupted. No t5-rplx failure was observed; that is
not evidence of its cause or correction. The already-integrated frame-test
correction remains for the parent's combined verification.

The first affected analysis found one style diagnostic at jellyfin.dart:720:
curly_braces_in_flow_control_structures. Braces were added around the existing
single rethrow statement; there is no behavior change. Analysis is rerun after
that cleanup. Full/affected tests above cover the same behavior; they are not
rerun merely to change the independent old frame-test outcome.

Final affected analysis passed with no issues. Changed-file formatting passed
with zero changes. The exact production/test source hashes are recorded in
source-hashes.json. Complete raw command logs are also retained as deterministic
gzip files under logs/; log-archive.json maps each raw hash to its archive hash.

## Fresh review and handoff

The one authorized fresh reviewer completed on 2026-11-13 using codex /
gpt-6-astra / high. It reviewed the complete original-base diff through
`563f1f3d4e69354a8f7a64df4bb2f51e33f6a4bc`, including the saved evidence.
Correctness and regressions, ticket fulfillment, and software design each
received an original `pass` verdict. There were no findings, required changes,
material in-scope gaps or user decisions. No fix stage was needed.

`review-original.json` preserves the review's exact final-message text.
`review.json` records its SHA-256 hash, returned thread link, launch settings,
source item, original verdicts and disposition. The reviewer independently
checked all 18 archived logs and raw hashes, four source hashes and the full
saved diff. It ran no builds, analysis or tests and made no edits.
`implementation-check.json` retains the successful complete whitespace check
and full diff hash for the reviewed implementation commit.

The remaining handoff commit adds only evidence and ticket notes; production
and test source remain unchanged from the reviewed commit. The final complete
original-base-to-final-HEAD whitespace check, clean-checkout result and source
hash verification are retained in `/tmp/bookfin-t9-ftlz/final-check.json` and
the final handoff. No behavior rerun is needed for these evidence-only edits.

The full suite remains failing on the old tf-il7u assertion. The parent's
combined verification with its integrated test-only correction remains an
integration condition, not an in-scope review gap or a passing test claim.
Browser execution, native input-copy and compact-page retention costs, and
the absence of latency, frame-budget, total-heap and million-record stress
measurements remain explicit limits. The ticket stays `in_progress`.
