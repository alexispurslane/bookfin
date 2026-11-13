# Incremental persistence with complete action retention

Historical save implementation: `t6-t9po`. The November 13 section below
records the current restoration behavior from `boo-0931`. Implementation base: `d69cfb3`.
The user selected Design A on November 3, 2026.
Every immutable action remains stored, including every superseded position.
Storage growth remains an accepted cost.
The plugin package, HTTP routes, action format, and user choices do not change.

## One owner

`LocalResumeStore` remains the only owner of account record transitions.
It serializes reads, migration, writes, acknowledgments, conflict choices, and discovery updates.
`RecordJournal` remains its existing model of retained actions and their derived state.
`RecordDatabase` executes the owner's changes in a SQLite transaction.
It does not decide which version wins or maintain another independently editable record model.

A retained action describes one immutable record change.
A pending identity names a retained action without confirmed upload acknowledgment.
Causal coverage is the last contiguous applied action number for each installation.
A current version names an applied action that another observed action did not replace.
A held action waits for causal coverage that its context requires.
The discovery cursor is the last server sequence durably admitted locally.

| Table | Durable meaning | Ordinary position save | Acknowledgment |
| --- | --- | --- | --- |
| `record_accounts` | Account identity, installation identity, discovery cursor, and non-record configuration | Update small metadata row | Update small metadata row |
| `record_actions` | Every immutable action payload and its pending flag | Insert each new action individually | Update only the named action's pending flag |
| `record_versions` | Current action identities for each record address | Replace identities for changed records only | No change |
| `record_coverage` | Contiguous applied action number for each installation | Replace coverage for advancing installations only | No change |
| `accounts` | Previous whole-account payload awaiting migration | No write after migration | No write after migration |

The owner records newly admitted actions and changed record addresses and coverage.
The database commits only those changes, together with pending acknowledgments and metadata.
The owner clears that change list only after the transaction completes.
Reading pending uploads or the discovery cursor does not write the database.

The journal indexes held actions by the installation and action number they require.
New coverage wakes only actions whose required number is now available.
Current version identities form a set, not an application-order history.
Their durable ordering is canonical, so restart replay can apply concurrent versions in a different order without rejecting the account.
An ordinary position change never scans the retained action table or iterates all retained journal actions.
The owner still constructs visible snapshots from current versions.
Work for those snapshots therefore depends on current records, not only the one changed position.
This is not a constant-cost promise for unlimited visible history or unlimited conflicts.

## Migration and failed writes

Opening a version-one SQLite database creates the new tables through the schema upgrade transaction.
The owner then migrates each account when that account is first read or changed.
It reads either the old SQLite payload or the legacy preference payload.
An existing SQLite payload takes precedence over preferences.

Migration admits every retained action through the existing action and record-value validators.
This includes superseded actions, held actions, and actions awaiting upload.
Legacy snapshots without a journal create their normal initial actions.
The owner derives current versions and causal coverage from the admitted actions.
One transaction inserts all normalized rows and removes that account's old SQLite payload.
The transaction preserves the installation identity, pending identities, and discovery cursor.
Other accounts remain separate and untouched.
Preference data remains available as the legacy source until SQLite supplies the migrated account.

If migration fails, SQLite rolls back every new row and retains the complete old payload.
If an ordinary save or acknowledgment fails, SQLite rolls back its related state together.
The owner discards the affected account's mutable cache and reports the original failure.
The next operation reloads durable state rather than using a half-applied in-memory change.
The listening and reading owners retain their failed account-owned snapshots for retry.
Their accepted-snapshot mechanism still controls deletion authority.
Merely reading or rejecting a refresh does not authorize deletion of unseen records.

Startup rejects malformed retained actions or mismatches between durable derived rows and replayed actions.
It reports an ordinary storage-format error and does not replace the stored account.
It does not silently fall back to older preference records after finding a normalized account.
Invariant failures remain programming errors and are not converted into successful saves.

## Invariants and guards

Public admission checks remain enabled in every build.
They check action structure, account ownership, immutable duplicates, record addresses, and record values.
Migration applies the same checks to all old actions.
Debug assertions check local causal application preconditions without scanning the retained journal.

The module maintains these invariants:

1. Every pending identity names a retained immutable action in the same account.
2. Every covered action number has a retained action, with no missing earlier number from that installation.
3. Every current version is a retained applied action.
4. Every unapplied action remains indexed by missing causal coverage.
5. Current records, causal coverage, pending state, discovery cursor, and configuration agree with the committed transaction.
6. Visible snapshots derive from current versions under the same owner.
7. A failed transaction never changes accepted-snapshot deletion authority.

`RecordJournal.checkInvariants()` checks the journal's internal relations on demand.
`LocalResumeStore.checkInvariants()` serializes an explicit comparison of cached and durable state, then runs SQLite's integrity check.
Both methods remain available in release builds.
Ordinary saves and acknowledgments do not run a whole-history invariant check.

## Startup, memory, and storage costs

The owner loads, validates, and replays each account's complete retained journal once when that account enters its cache.
Startup must read and validate every retained action.
Replay also processes each action's causal dependencies.
Migration additionally inserts all actions and derived rows once.
The cache holds every decoded action, current versions, pending identities, and the held-action index.
Memory therefore grows with retained history across all accounts loaded by that owner instance.
Transient startup allocations also include decoded database rows and defensive action copies.
There is no fixed lifetime limit for startup work, memory, or storage.

The cache lasts until the owner instance ends or an unsuccessful mutation discards the affected account.
An unsuccessful mutation can therefore make the next operation pay the full startup cost again.
The preference-only fallback retains its whole-payload behavior and re-reads preferences for existing recovery behavior.
The incremental performance claim applies to the SQLite path used by Android, not the preference-only fallback.
The whole-journal database export used by tests remains intentionally proportional to history.
The ordinary SQLite save path does not use that export.

## Verification and evidence

The first two behavior tests reject replacement of the old account payload through actual SQLite triggers.
Both fail on the base implementation when it attempts a whole-account write.
They then pass for position saves and synchronization acknowledgments with incremental persistence.
The tests inspect durable records and pending state after closing and reopening SQLite.

Additional SQLite tests exercise migration rollback, version-one upgrade, rejected superseded values, retry after repair, and failed position and acknowledgment transactions.
They also exercise held deletions across restart, reordered discovery, late uploads, and altered duplicate actions.
One additional red test exposes a valid conflict rejected after held-action replay changes the application order.
Canonical current-version identities fix that restart failure without changing action payloads or conflict choices.
Existing coordinator choices and stale or rejected refresh races run with both preferences and SQLite.
The existing sync regressions remain in the project suite.
The final project suite passes 425 tests with three opt-in skips, and `flutter analyze --no-pub` reports no issues.
The opt-in measurement and actual-plugin regression pass separately.
Exact command output is retained in `tool/evidence/sync/incremental-checks.txt` and `tool/evidence/sync/incremental-plugin-checks.txt`.
The meaningful failures remain in `tool/evidence/sync/incremental-red.txt` and `tool/evidence/sync/incremental-conflict-red.txt`.

The opt-in host measurement remains `test/research/journal_growth_measurement_test.dart`.
The original whole-payload baseline remains `tool/evidence/sync/journal-growth.json`.
The incremental run is `tool/evidence/sync/journal-growth-incremental.json`.
It retains the same 60, 600, 3,600, and 21,600 resume-action profiles and their protected records.
The 21,600-action profile with only 16 initially pending identities remains included.
Every original action and pending identity is compared after restart.
Acknowledgment profiles separately check exact retained actions and empty pending state after restart.

Test-owned SQLite triggers count actual changed rows and logical field bytes.
They reject retained payload updates and action deletion during measurement.
Row-work totals include the two warmup saves and eight timed saves.
Acknowledgment samples include loopback HTTP validation, one upload, durable acknowledgment, and discovery.
They do not isolate SQLite acknowledgment latency from HTTP work.
The measured field-byte counts are not filesystem, WAL, flash, or battery measurements.
WAL means SQLite's write-ahead log.
Restart timings use a new owner and reopened SQLite with a warm host filesystem, not a cold process or device launch.

`tool/evidence/sync/incremental-actual-plugin.json` records the actual disposable plugin regression.
It uses the existing `Bookfin.Storage_0.1.1.0.zip`, not a new package or API.
The owned Jellyfin process stops after the test, and ports 7464 and 7465 are free afterward.
No Android device action, installation, acceptance port, public service, or live server is involved.

Host timings are neither Android acceptance nor Android latency, battery, or flash guarantees.
No compaction, checkpoints, coalescing, expiry, coverage campaign, or mutation campaign runs in this ticket.
The parent still owns independent review, integration, Android acceptance, and ticket closure.

## Bounded host results

The final incremental host run completed on November 3, 2026.
Each save median uses eight samples after two warmup saves.
The baseline and incremental measurements are separate host runs, not a paired device benchmark.
The single-pending synchronization medians use separate fixtures with the same retained history and one new pending action per sample.
Their timing includes loopback HTTP work, not only the SQLite acknowledgment.

| Retained resume actions | Initial pending identities | Baseline save median, ms | Incremental save median, ms | Single-pending synchronization median, ms | Normalized restart, ms |
| --- | --- | --- | --- | --- | --- |
| 60 | 103 | 5.61 | 1.59 | 5.90 | 5.76 |
| 600 | 643 | 15.79 | 1.26 | 5.93 | 17.82 |
| 3,600 | 3,643 | 83.40 | 1.45 | 5.71 | 79.89 |
| 21,600 | 21,643 | 492.05 | 1.24 | 5.21 | 427.56 |
| 21,600 | 16 | 477.84 | 1.75 | Not separately measured | 410.10 |

Every profile's ten saves insert exactly ten action rows and change ten rows each for metadata, current versions, and causal coverage.
No retained action payload is updated or deleted.
Each acknowledgment fixture records eight pending-flag updates across eight timed synchronizations.
Migration plus first read takes 16.07 to 666.87 ms across the fully pending fixtures.
The 21,600-resume fixture with 16 pending identities takes 636.09 ms to migrate and first read.
These startup costs remain because the owner admits and caches the complete retained journal.
SQLite file sizes include the test audit table and freed pages from the migrated legacy payload.
Logical export byte counts describe journal plus metadata, not a complete materialized snapshot or bytes rewritten by each save.


## November 12 acknowledgment batching

The approved `boo-s11s` follow-up extends LocalResumeStore with group acknowledgment.
All verified identities in one upload group clear their pending flags in one existing
SQLite transaction. A failed transaction leaves the entire group pending. This does
not change action retention, causal coverage, current versions, migration or startup
replay. Transport never edits the journal directly. The additive plugin protocol and
its legacy fallback are documented in `plugin/Bookfin.Storage/README.md`.

## November 13: restore committed current state (boo-0931)

This section supersedes the startup and memory costs described in the November 3
implementation above. The retained-action format, server API and retention policy
are unchanged. SQLite keeps every original immutable payload indefinitely.

A normalized account now restores the current versions, causal coverage, pending
identities and discovery cursor that its transactions already committed. It decodes
only current versions and held actions. A held action is an action whose context
still needs a missing predecessor. Superseded payloads stay on disk. The journal
also releases payloads that cease to be current after a successful save, so normal
use does not grow a second complete journal in memory.

LocalResumeStore still owns each transition, its database transaction, failure
rollback and the cached views. RecordJournal owns causal admission and conflict
rules. Its disk-aware local-change and receive operations fetch temporary original
payloads before applying a change. A local change can release a held remote action,
so both operations use the same original-payload path. Callers cannot separately
install retained originals or mutate a second action inventory.

| Need | Payload access |
| --- | --- |
| Show current audio and reading records | Restore current identities and their payloads, including deletion actions and unresolved competing versions |
| Hold an action with missing predecessors | Restore only actions beyond committed coverage, then rebuild their dependency index |
| Upload pending actions | Restore pending identities first; load and validate their payloads when transport requests the upload snapshot |
| Receive an immutable duplicate | Look up its original by account and identity; reject changed content or a covered identity whose original is missing |
| Validate a preserved version | Load named originals, including those needed by held actions that either a local change or received page can release |
| Find the last local position | Use the installation, record and descending sequence index, including local actions superseded by remote versions |
| Adopt a server copy or recover kept records | Read the retained journal explicitly and use the existing replay and repair paths |
| Verify invariants | Independently replay retained actions and compare current versions, coverage, pending flags, resident payloads and held dependencies; also check lookup columns and SQLite integrity |

### Indexed access and the one-time upgrade

Schema version four adds lookup columns to each retained row: its installation,
sequence and record address. These columns derive from the immutable payload;
they are not another authority. New actions write them with the original payload
in the existing transaction. The explicit full checker compares them to that
payload. Separate indexes support sequence ranges, last-local lookups, record
addresses, pending identities and rows needing recovery.

The upgrade decodes old payloads in batches of 256 in workers, then builds the
indexes inside SQLite's schema-upgrade transaction. It changes no payload bytes.
Malformed payloads keep their bytes and get missing lookup columns, which route
the account through existing salvage. An upgrade failure rolls back the new
columns, indexes and schema version; the original rows remain readable for retry.
The measurement below reports this one-time cost separately.

Normal restoration seeks to each distinct installation and record address, then
seeks directly to the required ranges. It does not enumerate historical identities
or count all retained rows first. A dedicated partial index checks for missing
lookup metadata. The first measurement exposed SQLite choosing another index and
scanning every retained entry for this check. A failing instruction-count regression
caught that scan; the query now selects the partial index explicitly.

The worker reads one snapshot through an explicit read-only transaction. This is
necessary because sqflite's transaction helper omits BEGIN for read-only
connections. If the worker cannot open a connection, or an injected connection
factory holds an unsendable close lock, the store uses its existing connection for
the same bounded reads and keeps payload decoding in workers. Both connections
use the same validation of the last local action against its requested record and
installation. Restoration contract failures propagate as bugs; they are never
retried as success.

### Recovery and limits

Missing current references or malformed needed values use the existing retained
copy and salvage process. A corrupt payload discovered by a later required lookup
fails that operation without overwriting the original bytes. After damaged pages
force a new database file, recovery rejoins the just-damaged file's authoritative
originals with resident and uncommitted actions. The storage owner supplies a
reader for those originals; archived rejected copies never enter that selection.
The full replay must reproduce the cached current identities and coverage before
any replacement is committed. If predecessors cannot be read, reconstruction
reports failure and retains the cached accounts and complete damaged file for
retry. It does not convert visible values into a replacement journal: that would
omit known deletions and unresolved resume conflicts. Once the retained originals
become readable, retry commits the complete reconstructed state atomically.

The normal cache contains current and held payloads plus pending identities.
These sets can themselves grow. A large pending upload snapshot still needs all
of its pending payloads because that is the current transport interface. Preference
and web storage retain their existing whole-value behavior. Migration, explicit
verification and repair deliberately remain proportional to retained history.
The admission and commit encoding work tracked by te-6j4k remains separate; this
ticket moves required retained-payload reads and validation into workers and does
not redesign received-page admission or the plugin boundary.

### Host evidence

`test/research/current_restore_measurement_test.dart` uses real LocalResumeStore
reads after SQLite close/reopen. Each profile keeps 43 current record addresses:
40 visible records with selected values, two deletions and one unresolved resume.
There are 44 current versions, 16 pending identities and one held action. Each
profile compares every original payload byte after reopening.

The experiment captures production SQL and results. It then re-executes those
queries against the unchanged fixture with SQLite's instruction counter enabled.
This checks database work in addition to payload reads. The full-replay comparison
reads, decodes, validates and admits the complete journal and derives both domain
views in a worker. Three warm-host-filesystem samples describe host debug/test
cost, not a cold process launch or Android latency, frame time, battery or flash.

The machine-readable results are in `tool/evidence/sync/current-restoration.json`.
The existing save/acknowledgment experiment is separately retained in
`tool/evidence/sync/journal-growth-current-restoration.json`. Its SQLite triggers
confirm that ten ordinary saves insert ten new action rows and never update or
delete an original payload. Grouped acknowledgment and page/cursor atomicity remain
covered by the unchanged boo-s11s suites and the required store suites.

| Retained resume actions | Restore median, ms | Full-replay median, ms | One-time v3 upgrade, ms | Payloads read | SQLite instructions |
| --- | --- | --- | --- | --- | --- |
| 60 | 6.289 | 5.923 | 10.979 | 45 | 8,577 |
| 600 | 6.076 | 19.201 | 19.453 | 45 | 8,577 |
| 3,600 | 5.420 | 82.140 | 59.362 | 45 | 8,577 |
| 21,600 | 4.734 | 459.020 | 318.746 | 45 | 8,577 |
| 216,000 | 5.032 | 4785.979 | 3096.160 | 45 | 8,577 |

All five profiles retain the same current records, pending identities and held
action described above. The SQL instruction count stays at 8,577 across these
profiles. Index depth, filesystem state and host load can still affect elapsed
time. The largest one-time upgrade takes about three seconds on this host; it
is not included in the normalized restore time.

## November 13: continue discovery past unreadable objects (boo-3y46)

A structurally valid discovery page can contain an object this build cannot
interpret. The store retains that object's complete wire fields, including the
unchanged payload string, in `record_objects`. Schema five adds this table and
its account/count index. A page commits its retained originals, admitted actions,
current state and cursor together. A repair that accepts a server copy belongs
to that same transaction, including the archive of the rejected local copy.
No original is deleted, coalesced or expired.

The existing owners keep their responsibilities. RecordTransport validates page
boundaries and wire ordering. LocalResumeStore owns admission, raw retention,
transactions, retries and recovery. RecordJournal decides causal admission and
whether a preserved conflict version belongs to the same record and was observed.
RecordSync owns scheduling and the account's narrow count signal. The Sync page
subscribes to that signal and shows a quiet count of server identities this build
cannot read. Repeated delivery does not increase the count. Distinct server events
for the same identity remain retained separately, including tombstones.

A valid unknown record kind still enters the journal, advances real causal
coverage and stays hidden. Malformed JSON, an unsupported envelope version or an
invalid known value supplies no causal coverage. A malformed preserved-version
reference is retained without admission. A preserved version whose original has
not arrived yet waits in retained storage without being called unreadable; the
end-of-discovery retry admits it once the original arrives. Other absent causal
predecessors retain the journal's existing waiting behavior. A server tombstone
never deletes local actions, history, bookmarks or pending writes.

Native startup restores the committed journal state and a count of retained
wire events. It does not read their bodies. The quiet unreadable-identity count
uses the table's index. Explicit retry, requested after startup and after completed
discovery, reads and interprets retained bodies in a worker. Successful
interpretation changes only the derived unreadable flag, keeps the original bytes
and admits the action through the journal. The preference fallback keeps the same
originals in its existing atomic account value. Migration moves them into SQLite.

The existing kept-copy and authoritative-file recovery paths also carry these
originals. Cached native accounts remember how many wire events they retained.
Before a normal save, migration or account repair writes a prepared commit, the
store stages that commit's original objects for file reconstruction. Migration
cannot leave those objects only in a prepared commit while reconstruction reads
another input. The staged objects remain available until the write succeeds.
Reconstruction must recover at least those originals as well as reproduce current
versions and coverage. Missing original pages fail reconstruction; the cached
records and damaged file stay available for retry. Normal account repair copies
wire originals to its archive and leaves them in the live account too. Archived
objects never replace a live original with the same identity and server sequence.

Unreadable remote records have their own outcome. A completed exchange still
records its completion time. If an upload finds that its immutable identity was
retired on the server (HTTP 410), the action stays pending and discovery continues
before the upload failure is reported as `uploadRejected`. That failed exchange
does not advance the last successful sync time or schedule an immediate retry.
Live Playback and reader sessions still refresh the committed records, through
the same refresh operation used after a completed exchange. The Sync page keeps
the quiet unreadable count and shows the incomplete upload without claiming
that the phone matches Jellyfin. `remoteUnreadable` means a completed exchange
with unreadable remote objects. Other upload failures keep their existing
transport behavior. Missing plugin routes, malformed whole replies,
unsafe cursors, local storage failures and contract failures remain distinct;
contract failures are never caught as recoverable object formats.

The regression suite includes both legacy and batch discovery, later pages and
the next sync, exact retained payloads after SQLite reopen, unknown kinds and
versions, malformed JSON and value types, tombstones, duplicate delivery,
account isolation, pending uploads, transaction rollback, server-copy repair,
causal gaps and conflicts, future interpretation, kept-file recovery and refusal
of incomplete reconstruction. A query-observation test confirms that reopening
and showing the count reads no retained wire body. The required full host checks
and review evidence are recorded in `.tickets/boo-3y46.md`. No plugin API or source
change, device check, deployment, coverage or mutation run is part of this ticket.
