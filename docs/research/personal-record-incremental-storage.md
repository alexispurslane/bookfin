# Incremental persistence with complete action retention

Ticket: `t6-t9po`. Implementation base: `d69cfb3`.
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
