# Private playlist checkpoint continuation

Ticket: t3-7fv1, under boo-p58t. Starting commit:
`c13748198f0b7f73ad0ba1ec2b7ac84fbe989627`.
Measurements: November 2, 2026, in the isolated t3-16d73e22 worktree.
All HTTP requests used a new synthetic fixture on `127.0.0.1:7364`.
Earlier stopped fixtures were not opened or changed.

## Result

One candidate now passes finite checkpoint, merge, deletion, delayed-retry,
batching, and a specified upgrade exercise. It does not establish bounded
protocol storage over the lifetime of an installation. The exact failing
schedules are below. Production personal-record sync remains gated.

The candidate uses existing private playlists. No new plugin was selected or
installed. Enhanced was also omitted from this fresh fixture. Listening work is
unrelated and remains unblocked. These results do not reject every possible
existing-storage protocol or establish that a plugin has lower total risk.

## Research conditions, not product policy

The two device identities are exactly `device-a` and `device-b`. Both remain in
every coverage summary, including when one contributes no actions. There is no
automatic expiry, device retirement, history pruning, or discarded pending
action. A third identity is outside this experiment, not a proposed product cap.

These are logical journal authors sharing Alice's synthetic account. Bob is the
privacy observer, not a third journal author. Two Android installations were not
run, and Jellyfin's HTTP client device header is not the journal identity.

The authors are cooperative and keep their action identifiers immutable.
Concurrent versions remain unresolved. A delete concurrent with an edit retains
both versions, including the deletion witness. No production conflict screen,
winner rule, conflict resolution, or recovery policy was chosen.

The experiment limits each published name to 65,536 UTF-8 bytes. This is a
research envelope based on an earlier accepted sample, not a measured Jellyfin
maximum or a proposed user quota. An oversized name fails; it is never truncated.

## One journal and one coverage model

An action identifier contains a device identity and a positive sequence number.
A causal context contains the sequence prefixes that the author has observed.
A sequence prefix is every action from one through the stated number.

A checkpoint contains the accepted sequence prefix for each device, the current
record versions, and actions waiting above a missing sequence or dependency.
Waiting actions do not increase accepted coverage. The earlier action or a valid
checkpoint covering it must arrive before those actions affect records.

Each record keeps its causally latest versions. A later action replaces only
versions in its causal context. Independent edits therefore retain both values.
A delete is a version without a live value. This candidate retains that deletion
witness in the same checkpoint representation, not in a second deletion ledger.

Checkpoint merging combines coverage and retains versions that the other
checkpoint has not superseded. Buffered actions use the same acceptance rule
after merging. Covered retries have no effect. The two device prefixes are not
replaced with one global highest action number.

Publication creates a short private staging playlist, writes the whole sealed
batch or checkpoint into its name, and reads the exact name back. Immutability
is an app convention, not a server-enforced permission. Cleanup requires a
published checkpoint with the same state as the discovered journal. A whole
batch remains until every contained action is covered. An older checkpoint is
removed only when merging it adds no information to the replacement.

Equivalent checkpoint writers choose the smallest playlist identifier to keep.
This prevents two cleaners from choosing only their own equivalent copy and
deleting each other's last copy. Tests exercise this rule and stale-cleaner
protection. Simultaneous network execution of two cleaners was not measured.

The server playlists are the only remote representation. The ignored
`finite-state.json` is a measurement oracle: it holds expected synthetic results
for upgrade assertions. Discovery and cleanup do not read it to recover records.
There is no second durable index, new app framework, or production integration.

### Invariants

`Journal.check_invariants()` checks these conditions on demand. It also works
under Python's `-O` mode, which removes ordinary debug assertions.

- Coverage contains nonnegative prefix counts for both fixed identities.
- Every retained record version is covered, has covered dependencies, and uses
  the same record key and action identifier as its enclosing entry.
- No retained version is causally superseded by another retained version.
- Every buffered action is above its author's accepted prefix.

The checker is not a recovery path. A failure is a research-harness bug.
Ordinary public-input guards reject unknown identities and malformed action
numbering. This is not a validator against malicious checkpoint authors.
In particular, a covered retry is trusted to retain its original payload;
per-action hashes are not retained forever to detect forged identifier reuse.

## Runtime evidence versus model evidence

All JSON evidence below is in `tool/research/sync/evidence/`.

| Exercise | Exact observation | Evidence boundary |
| --- | --- | --- |
| Missing earlier action | Store device-a:2 before device-a:1. The first checkpoint has coverage 0/0 and buffers device-a:2 | Real 12.3.0 objects; Python reducer interprets their payloads |
| Independent checkpoints | Two checkpoints computed from the same device-a:1 base retain device-a:2 and device-b:1 edits together | Real publication and discovery, controlled sequential HTTP requests, not simultaneous writes |
| Delete and collect | device-b:2 explicitly observes both edits and deletes the bookmark; six covered batch/older-checkpoint objects are deleted | Real DELETE calls and subsequent 404 reads |
| Delayed retry | After collection, publish device-a:1 twice. Fresh discovery still has zero live bookmarks, one deletion witness, and coverage 2/2 | Real duplicate objects, not a newly injected socket-level lost acknowledgment |
| Remove retries | Delete the two covered retry objects and reconstruct from the remaining checkpoint alone | Real server readback; same result without local journal recovery |
| Delete concurrent with edit | Preserve both deletion and unseen edit as an unresolved conflict | Unit/model evidence only |
| Equivalent and stale cleaners | Keep one deterministic equivalent checkpoint; a stale checkpoint cannot authorize deleting a newer checkpoint | Unit/model evidence only |

`finite-schedule.json` records the runtime schedule and exact owner/Bob privacy
checks. The owner receives 200 with the exact checkpoint name; Bob receives 404
without that payload. The observer checks decoded JSON strings recursively.
The earlier `playlist-objects.json` remains the evidence for a real unread create
acknowledgment. This follow-up does not relabel ordinary repeated creates as that
network fault.

### A discovered search limitation

The first workload attempt left five covered batches after cleanup. A second
pass found and removed those five; the checkpoint state had not changed.
The repeated attempt added an oracle assertion against every acknowledged
publication identifier. That assertion caught an incomplete inventory before
cleanup. No protocol data was lost or silently treated as covered by that check.

`finite-pagination-counts.json` records a quiescent 12.3.0 search with 16 workload
objects. With `SearchTerm=BookfinFinite-t3-16d73e22-workload` and `Limit=4`, offsets
0, 4, and 8 each return four items and total 12; offset 12 returns none.
The same search with limit 128 returned all 16 in the diagnostic run. This is not
the earlier experiment that changes objects between pages. No server-side cause
is asserted here.

`finite-unfiltered-counts.json` instead records 17 unique owner playlists with
both page sizes: the 16 workload objects plus one schedule checkpoint.
The final candidate enumerates all owner playlists, then decodes the namespace
locally. It does not depend on server search for completeness. Its final
inventory matched every acknowledged workload publication identifier.

Two equal scans are a measurement of quiescence, not a server snapshot guarantee.
Continuous mutation, other owner playlists, retries, or abandoned staging
objects can increase discovery work. The script aborts after 128 requests rather
than authorizing cleanup from a partial scan. That is a research safety budget,
not a production object cap. The earlier offset-mutation counterexample remains
valid. No bounded discovery latency during continuous writes is claimed.

## Measured batching costs

The workload creates 100 bookmarks on each device. Each bookmark receives six
values including creation, followed by deletion of 20 bookmarks per device.
That is 1,240 actions, 160 live bookmarks, and 40 deletion witnesses.
Each value contains a revision label and 64 padding characters. This is synthetic
bookmark data, not a measurement of full reading positions or listening history.
No user-visible history was pruned to achieve these counts.

Each device seals at most 100 actions per batch. Its 620 actions create seven
batch playlists. Two independent checkpoints are then joined into one replacement.
`finite-workload.json` records the measured costs, not a one-playlist-per-event
estimate.

| Stage | Batch playlists | Checkpoint playlists | Total workload playlists | Stored name bytes, UTF-8 | Playlist file bytes |
| --- | ---: | ---: | ---: | ---: | ---: |
| Before collection | 14 | 2 | 16 | 315,136 | 320,896 |
| Replacement publication peak | 14 | 3 | 17 | 361,084 | Not sampled |
| After collection | 0 | 1 | 1 | 45,948 | 46,308 |

Playlist file bytes count the matching XML/M3U/NFO files. They exclude database
indexes, database journals, logs, filesystem allocation, and all other fixture
data. Stored name bytes count the serialized payload, not an entire disk quota.
The table excludes the separate schedule checkpoint. The retained fixture has
two private checkpoint playlists in total.

| Discovery stage | Page size | Complete scans | HTTP requests | Owner items visited | HTTP response bytes |
| --- | ---: | ---: | ---: | ---: | ---: |
| Before collection | 4 | 2 | 10 | 34 | 996,820 |
| Before collection | 128 | 2 | 2 | 34 | 996,432 |
| At collection | 4 | 2 | 10 | 36 | 1,141,014 |
| After collection | 4 | 2 | 2 | 4 | 146,184 |

Owner-item visits include the unrelated schedule checkpoint, because discovery
now scans all owner playlists. Response bytes include Jellyfin response objects
and JSON escaping, but not HTTP headers. Exact multiples of the page size need
an extra empty request to establish the end. Creation, update, positive readback,
deletion, privacy checks, and the separate peak inventory are additional calls;
this table is discovery work, not total request cost or a latency benchmark.

These counts satisfy the engineering measurement prerequisite for tb-887c.
They do not settle whether ordinary-playlist visibility is acceptable to the
user. The payload remains an ordinary playlist name after batching. Owner
rename, deletion, and explicit sharing remain the previously measured risks.

## Exact remaining bound failures

The target bound is protocol overhead relative to current records, unresolved
conflicts, and the two retained device identities. User-visible retained history
is a separate quantity. A finite workload is not proof of that lifetime bound.

`finite-model-costs.json` is explicitly model evidence, not a server load test.
Its first schedule repeatedly creates and deletes a new bookmark on device-a.
Every action is present and covered, device-b remains at prefix zero, no live
bookmark remains, and no conflict remains. This candidate still retains one
deletion witness per deleted record.

| Distinct bookmarks created then deleted | Actions covered on device-a | Deletion witnesses | Checkpoint state bytes, UTF-8 |
| --- | ---: | ---: | ---: |
| 10 | 20 | 10 | 1,567 |
| 100 | 200 | 100 | 15,259 |
| 1,000 | 2,000 | 1,000 | 153,961 |

The last checkpoint exceeds the experiment's 65,536-byte publication envelope.
This is not an observed Jellyfin size rejection. It shows that this candidate
does not compress deleted-record overhead into the fixed device summaries.
Sharding an ever-growing set of witnesses would only move that growth to more
playlists. No alternate compression protocol was implemented in this task.

The second schedule withholds device-a:1, then delivers device-a:2 through
device-a:1001. All 1,000 later actions remain buffered and coverage remains 0/0.
The checkpoint state reaches 134,854 bytes. Discarding those actions or advancing
coverage would violate this experiment's no-loss condition. The workload does
not establish a bound on unresolved gaps, abandoned staging objects, late retry
copies, or checkpoint copies under continuous writers.

These are concrete blockers to promoting this candidate as a complete bounded
protocol. They are not reasons to invent a retention duration or expire a device.
tb-5fyd records the product question; further engineering must first distinguish
necessary user choices from limitations of this particular summary.

| Storage direction | User-visible benefit | Measured or unresolved cost |
| --- | --- | --- |
| Continue existing private-playlist storage | No new server extension; 1,240 actions reduced to one 45,948-byte checkpoint for this workload | Ordinary playlist management can expose or remove data; all-owner discovery; deleted-record and gap growth remain unresolved |
| Accepted small-plugin fallback, not selected | A dedicated record namespace could avoid ordinary playlist entries | Requires implementation, installation, compatibility and authorization testing, and maintenance; no size, speed, privacy, or lower-total-risk measurement exists for that unbuilt plugin |

Both directions must preserve offline actions and unresolved conflicts. A plugin
does not automatically solve deletion-summary growth, history retention, or
long-offline recovery. No plugin code, installation, or production storage choice
was made. This comparison supplies costs to the parent, not a settled winner.

## One specified upgrade pair

Both official macOS ARM64 archives are pinned in the research flake and
`sources.json`. No toolchain was installed globally.

| Runtime version | Official binary archive | SHA-256 in Nix SRI form |
| --- | --- | --- |
| 12.3.0 | jellyfin_12.3-arm64.tar.xz | sha256-Lrf3QHcecgaI+Vj+6wD4BZ6KhrAKOIp5iUzMcYi9erk= |
| 12.4.0 | jellyfin_12.4-arm64.tar.xz | sha256-wQfU4Nhei6EpJMkRTSqK1D6dg1QKZ5I9vveIuTMR/i0= |

The fixture was seeded and measured on 12.3.0. It was stopped cleanly, then the
same directories were opened with 12.4.0. A further clean 12.4.0 restart used
those directories again. The server identifier was checked on every phase.

`finite-before-upgrade.json`, `finite-after-upgrade.json`, and
`finite-after-new-restart.json` compare both checkpoint state hashes and exact
serialized payload hashes. Both namespaces retain their two device identities,
coverage, live values, and deletion witnesses. Owner reads remain exact 200 and
Bob reads remain 404 without the payload.

This establishes preservation of these two compacted samples across this one
pair and subsequent clean restart. It does not establish general Jellyfin
upgrade compatibility, Android behavior, every intermediate journal state,
process-kill durability, rollback, or migration of a plugin. The old binary was
not opened against data migrated by the newer binary.

## Verification and retained state

The research suite uses Python unittest through the pinned Nix research shell.
New behavior tests were observed failing before their implementations. The
optimized-mode invariant test also failed before the checker was corrected.
Final verification counts and commands are recorded in the ticket.
Coverage and mutation testing remain parent-owned and were not run.

After the final clean shutdown, the server process exited and port 7364 had no
listener. The ignored `.cache/sync/runtime/` remains private and restartable with
the pinned 12.4.0 binary. The directory is mode 0700. Generated password, token,
and expected-state files are mode 0600. No credential value is committed.
No existing stopped fixture, production service, browser, preview server,
emulator, or shared service was changed.
