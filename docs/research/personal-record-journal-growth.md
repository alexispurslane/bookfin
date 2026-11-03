# Retained personal-record journal cost

Ticket: `t6-t9po`. Read-only production investigation after plugin milestone `96d69c1`.
Measured on November 2, 2026 local time, November 3 UTC.
No production source, storage schema, HTTP contract, or retention rule changes here.
Neither design below is selected or implemented.

## What the measurement establishes

A journal action is one immutable change retained for synchronization.
A pending action is an action without a confirmed server acknowledgment.
A source second is one second of position within an audio file.
It is not necessarily one second of wall-clock listening time.

The existing playback owner received 20 synthetic decoder samples.
Each sample advanced the source position by 100 milliseconds.
Across 2,000 source milliseconds, the real store wrote two account rows and created two pending resume actions.
The test used the existing playback owner, its existing test decoder, and the real SQLite-backed store.
It did not wait for two seconds of real playback.

The production condition in `lib/playback/playback.dart` is:

```dart
    if (previous?.sourceKey != file.key ||
        previous!.milliseconds ~/ 1000 != milliseconds ~/ 1000 ||
        wasPlaying != _playing) {
      _save();
    }
```

where

- `previous` = the preceding accepted position within the current audio source, or null before a position exists.
- `previous.sourceKey` = the identity of the preceding audio source file.
- `file.key` = the identity of the audio source file selected by the current decoder sample.
- `previous.milliseconds` = the preceding position, in milliseconds within that source file.
- `milliseconds` = the current accepted position, in milliseconds within that source file.
- `1000` = the number of milliseconds in one source second.
- `~/` = Dart integer division, which removes the fractional part.
- `wasPlaying` = whether playback was active before this sample.
- `_playing` = whether playback is active after this sample.
- `_save()` = the playback method that queues persistence of its current record snapshot.

This condition uses source position, not a one-second wall-clock timer.
At normal speed, regular decoder samples can produce approximately one position save per listening second.
Speed changes, sparse samples, source transitions, pauses, and seeks change that rate.
The investigation does not measure the native decoder's sample timing on Android.

## Method and bounds

Run the host measurement from the checkout root:

```sh
nix develop --command bash -c '
  BOOKFIN_JOURNAL_GROWTH_EVIDENCE=tool/evidence/sync/journal-growth.json \
    flutter test --no-pub test/research/journal_growth_measurement_test.dart \
    --concurrency=1 --reporter expanded
'
```

The measurement uses Flutter host tests, Dart `3.13.3`, and macOS ARM64.
This is a debug/test process, not an Android release-performance measurement.
Every profile uses a fresh temporary SQLite database.
The measurement removes its temporary databases after all handles close.
It starts no HTTP server and uses no device or emulator.

Each profile seeds a chosen number of superseded resume actions.
Every profile also retains 46 other actions, including these records:

- Thirty-two listening history additions and one explicit history deletion.
- Eight audio bookmark additions and one explicit bookmark deletion.
- One reading bookmark addition.
- Two concurrent resume versions for a different edition.
- One received action whose preceding causal action is absent.

A causal action is a prior change required before applying a later change.
The absent preceding action stays absent throughout this measurement.
The received later action must remain retained but unapplied.
The unresolved concurrent resume versions remain separate.

The first four profiles retain all local actions as pending.
The final profile keeps the same full action list but only 16 pending actions initially.
This final profile models acknowledged backlog without deleting old actions.
The synthetic account and device identifiers are shorter than typical production identifiers.
Payload sizes are not a byte forecast for a particular account.

After one initial materialization, each profile performs two warmup saves.
Materialization means deriving visible records from the journal actions.
The profile then times eight sequential saves through the real `LocalResumeStore`.
Each save changes the main resume position by 1,000 source milliseconds.
The measurement separately times JSON decoding and `RecordJournal` reconstruction eight times.
That separate timing excludes the store's record-value validation, snapshot construction, and SQLite commit.

There are no performance pass/fail thresholds.
The action order is ordinary chronological order, not a worst-case causal ordering.
Eight samples do not establish statistical confidence, sustained throughput, or a lifetime storage limit.

## Observed host costs

One MB in this table means 1,000,000 bytes.
The payload is the complete JSON account row, not the database file size.
All latency columns use milliseconds per operation and the median of eight samples.

| Seeded resume actions | Initial total actions | Initial pending actions | Initial account payload, MB | Decode and journal replay, ms | Full store save, ms |
| --- | --- | --- | --- | --- | --- |
| 60 | 106 | 103 | 0.049 | 1.66 | 5.61 |
| 600 | 646 | 643 | 0.228 | 8.28 | 15.79 |
| 3,600 | 3,646 | 3,643 | 1.231 | 48.12 | 83.40 |
| 21,600 | 21,646 | 21,643 | 7.308 | 281.83 | 492.05 |
| 21,600 | 21,646 | 16 | 6.865 | 274.73 | 477.84 |

The 21,600-action offline profile submitted 58,481,548 logical payload bytes across its eight measured row replacements.
That is approximately 7.31 MB of complete account payload per measured save in this fixture.
It is not a measurement of filesystem, SQLite page, write-ahead-log, or flash writes.
The write-ahead log is SQLite's separate file for committed changes.
The measurement does not claim flash wear, battery cost, Android latency, or a particular number of dropped frames.

Reducing pending identities to 16 does not remove the retained action list.
The corresponding full-save median remains about 478 milliseconds in this host test.
Acknowledgment alone therefore does not remove the measured cost of reconstructing and serializing retained actions.

If one resume action occurs per source second, 21,600 actions represent six hours of source-position updates.
That is an input-size illustration, not six hours of observed listening.
Unbounded history and indefinitely offline pending changes cannot fit within an absolute fixed storage limit.
The useful design targets are avoidable resume growth and repeated work per update, without silent data loss.

## Why a save depends on retained actions

In `lib/playback/store.dart`, account loading contains these exact lines:

```dart
    final decoded = jsonDecode(raw);
...
    final journal = _journal(accountKey, decoded);
```

where

- `raw` = the entire saved JSON account row, read from SQLite or legacy preferences.
- `jsonDecode()` = the Dart JSON decoder.
- `decoded` = the decoded account state, including the complete retained action list.
- `accountKey` = the identifier for the server-and-user record owner.
- `_journal()` = the store method that reconstructs the journal and validates retained record values.
- `journal` = the reconstructed journal for this account.

Journal reconstruction receives the complete saved action list.
It tracks applied action sequences and rebuilds current record versions.
The store also validates retained values, including superseded values.
Those checks protect data integrity, but the current row representation repeats them for each save.

The persistence method contains these exact lines:

```dart
    final payload = jsonEncode(value);
    final database = await _storage();
    if (database != null) {
      await database.write(account, payload);
```

where

- `value` = the complete account state, including visible records, retained actions, pending identities, and discovery cursor.
- `jsonEncode()` = the Dart JSON encoder.
- `payload` = the resulting complete JSON account row.
- `_storage()` = the store method that returns its durable record database, or null for the legacy preference-backed path.
- `database` = that durable record database.
- `account` = the identifier of the account row being replaced.
- `database.write()` = the database method that replaces the account payload inside a SQLite transaction.

`LocalResumeStore` already owns the coherent account state and serializes changes.
The problem is not a second independent owner.
The complete retained journal is embedded in the one replaceable account row.
The investigation does not replace that model or remove validation.

## Restart preservation checks

After every profile, the measurement closes and reopens the actual SQLite database.
It checks every original action against the reopened action with the same identity.
It also checks these properties:

- Every original pending identity remains pending, alongside the ten new resume actions from warmup and measurement.
- Both concurrent resume versions remain unresolved.
- The later causal action remains retained without becoming visible.
- The explicit history deletion remains absent from the 31 visible history records.
- The explicit bookmark deletion remains absent from the seven visible audio bookmarks.
- The reading bookmark remains visible.
- A different account cannot read these records.
- SQLite integrity checks pass before closing and after reopening.

These checks bound the measurement's fixtures.
They are not a compaction proof, mutation campaign, or release acceptance.

## Two concrete designs for parent decision

The parent must choose the intended retention model before implementation.
Both designs keep one record owner and preserve every existing unsynced action.
A causal checkpoint is a durable summary of applied actions.
Causal coverage records the last contiguous applied action number per device.

| Design | Persistence and normal save | Retention result | Implementation and compatibility costs |
| --- | --- | --- | --- |
| A: Incremental retained journal | Store immutable action rows separately. Update current records, pending status, and causal coverage transactionally under the existing owner. | Keep every old action. Remove repeated whole-row work, but retain resume storage growth. | Local schema migration, transactional derived-state maintenance, and restart/invariant tests. The current server object API and action format can remain unchanged. |
| B: Versioned causal checkpoints | Use incremental rows plus a durable summary of safely acknowledged, superseded resume actions. Keep every unsynced action and protected record. | Reduce acknowledged resume growth. History, pending actions, deletion barriers, gaps, and unresolved conflicts still grow when their meaning requires it. | All costs of A, plus checkpoint semantics, causal-gap proof, old-client compatibility, recovery rules, and a versioned app protocol. The opaque plugin can hold bytes, but current app validation accepts only the present action format. |

Example A: after another source second, append one resume action and update the current position in one local transaction.
Keep all 21,600 preceding actions without rewriting their JSON in the account snapshot.

Example B: after a safe acknowledgment boundary, retain a durable causal summary instead of already superseded resume actions.
Keep every unsynced action, visible history entry, deletion barrier, missing-predecessor action, and unresolved conflict verbatim.
An old client must not mistake the summary for a complete ordinary action inventory.

Both designs require these protections:

- No expiry of listening history and no silent removal of unsynced changes.
- Atomic local persistence of records, pending changes, and the state needed to reconstruct them after restart.
- Explicit conflict resolution and deletion barriers that survive late uploads and missing earlier actions.
- Migration and compatibility tests before any production storage transition.

A is a candidate first step only if B keeps A's local row model unchanged.
If B requires a contradictory row model or migration, settle B's design first.
Neither option makes an absolute finite lifetime storage promise for unlimited user history or unlimited offline activity.
No journal compaction, checkpointing, or protocol change is implemented by this commit.

## Evidence

`tool/evidence/sync/journal-growth.json` contains exact byte counts, sample summaries, source hashes, and preservation results.
The host measurement completed in about 29 seconds on its recorded run.
The existing Android lane, current APKs, plugin package, and live servers remain untouched.
