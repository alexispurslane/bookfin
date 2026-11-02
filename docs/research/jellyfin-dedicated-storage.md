# Dedicated Jellyfin storage proof

Ticket: boo-dez0, supporting boo-p58t. Base commit: `756ae5f`.
Measured November 2, 2026, in the T3-prepared separate worktree.
The user selected storage separate from ordinary playlists, with history
retained until explicit deletion. This experiment follows those decisions.

## Result and scope

A small plugin now stores independent immutable objects in a dedicated,
authenticated account namespace. The bounded server experiment passes.
It covers isolation, concurrent durable writes, retry deduplication,
discovery, explicit deletion, delayed retries, and restart recovery.
It does not establish complete production sync or a lifetime storage bound.

All requests used a new disposable Jellyfin 12.4.0 on `127.0.0.1:7464`.
The fixture reserved 7465 but disabled HTTPS. Ports 7364 and 7365 were untouched.
No production account, server, plugin, device, or browser was used.
Earlier stopped fixtures were not opened or changed.

Source and reproduction commands are in `tool/research/plugin/`.
Sanitized evidence is in `tool/research/plugin/evidence/runtime.json`.
The existing research flake pins the official server archive and nixpkgs.
Its `sources.json` records the archive hash. The same pinned nixpkgs supplies
.NET SDK 10.0.401. The archive includes .NET runtime 10.0.14.
No global toolchain was installed. The plugin references the archive's Jellyfin
and SQLite assemblies without additional NuGet packages.

## Ownership and identity

An object is one immutable payload at one stable identifier.
A deletion marker retains knowledge that an object identifier is retired.
An operation is one Bookfin action, including a logical record deletion.
A replica is one Bookfin installation with persistent action numbering.
A causal context lists actions that an author had observed.

| Owner | State or decision | Cause of a change |
| --- | --- | --- |
| Jellyfin authentication | Account represented by a normal login token | Login, logout, or account administration |
| Plugin object store | Opaque payloads, object identifiers, transport sequences, deletion markers | Authenticated creation or explicit object deletion |
| Bookfin journal | Record versions, history events, causal context, unresolved conflicts | Bookfin actions and merges |
| Local pending-action store | Action identities, payloads, verified upload status | Durable local enqueue or verified server acknowledgment |

The plugin derives ownership from Jellyfin's authenticated account.
No route accepts a target account. A supplied `userId` query cannot switch
ownership. The experiment uses ordinary login tokens, not server API keys.
The fixture administrator's namespace remains empty.
The server operator still controls the database and plugin installation.
This is not protection from that operator.

Object identifiers come from the caller and remain unchanged on retry.
The local prototype uses replica identity and positive action sequence.
Its database is bound to the server, account, and replica identities.
Opening it for another scope fails. Before upload, it also confirms the remote
server and authenticated account.

A transport sequence is a positive integer within one account. It orders
storage changes for discovery, not Bookfin record winners. Account numbering
is independent. The plugin does not parse record semantics or compare clocks.
Bookfin owns record versions, causal order, and conflict decisions.

## Storage contract

All routes start with `/BookfinStorage/v1/objects` and require authentication.
The payload is a nonempty opaque string. Any JSON inside belongs to Bookfin.

| Request | Result | Effect |
| --- | --- | --- |
| PUT `/{id}` with a new payload | 201 with stored object | Atomically creates one object |
| PUT `/{id}` with its exact existing payload | 200 with original object | Adds no row or sequence |
| PUT `/{id}` with a different payload | 409 | Preserves the original object |
| PUT `/{id}` after deletion | 410 | Cannot restore the retired identifier |
| GET `/{id}` for a live object | 200 | Returns identifier, sequence, payload, deletion flag |
| GET `/{id}` for an absent object | 404 | Does not change state |
| GET `/{id}` for a deletion marker | 410 | Does not return the retired payload |
| DELETE `/{id}` | 204 | Replaces a live object or absent identifier with a permanent marker |
| DELETE `/{id}` again | 204 | Adds no row or sequence |
| GET with `after` and `limit` | 200 | Lists live objects and deletion markers after the cursor |

An identifier has 1–128 ASCII letters, digits, dots, underscores, colons,
or hyphens. The experiment permits 65,536 UTF-8 bytes per payload.
Larger payloads return 413 without mutation. Invalid identifiers and empty
payloads return 400. The HTTP body limit is 524,288 bytes, including escaping.
These are explicit experiment limits, not measured Jellyfin maxima or proposed
user quotas. The experiment never truncates a payload.

Discovery returns at most four objects per page, ordered by transport sequence.
The cursor is the last returned sequence, or the incoming cursor for an empty
page. Clients apply objects by identifier and sequence before persisting that
cursor. Deletion assigns a new sequence, so it remains discoverable even when
an earlier page already returned the object alive.

This is current-object discovery, not an event log or server snapshot.
A live object can transition once to a deletion marker. A client that sees
both applies the later sequence. The test changes seen and unseen objects
between pages and discovers the deletions and new objects. Continuous writers
can extend discovery. The 128-request safety budget fails rather than treating
a partial inventory as complete. No fixed discovery latency is claimed.

## Durability and invariants

One SQLite database under the server's data directory holds the objects.
Its primary key combines account and object identifier. A unique constraint
combines account and sequence. No ordinary playlist, library metadata,
custom preference, Enhanced document, or second discovery index backs it.

An immediate SQLite transaction serializes writers. The same transaction
assigns the next account sequence and changes its row. The next sequence comes
from the greatest retained account sequence. Permanent markers prevent deletion
from resetting that number. There is no separate sequence counter to coordinate.
Success follows transaction commit.

Connections use `synchronous=FULL`; the database uses WAL, SQLite's write-ahead
log. Eight independent HTTP workers create 80 objects without a lost acknowledged
write. Retry and delete races also use independent connections. A forced stop
preserves acknowledged objects and markers in this sample. That is not a power
outage or a proof about every filesystem and hardware failure.

The module's invariants are:

- One row exists per account and object identifier.
- Retained account sequences are positive and unique.
- An object has a nonempty payload or a deletion marker, never both.
- Stored account identifiers have 32 characters; object identifiers have 1–128.

Database constraints enforce key, sequence, and payload conditions.
Public HTTP guards validate identifiers and byte limits in every build.
Internal transaction checks use debug assertions, absent from release builds.
`ObjectStore.CheckInvariants()` remains callable in every build. It performs
an explicit integrity and row check. The fixture enables it when the store
opens, including after restarts. It is not an HTTP endpoint or recovery path.
The final direct database integrity result is `ok`.

The pending-action store has an explicit checker for scope, action identities,
and acknowledgment flags. No failed invariant is caught to recover.

## Deletion, conflicts, and pending actions

Logical record deletion differs from physical object deletion.
A logical deletion is a Bookfin action with causal context. It removes the
versions it observed. An equal-identity retry of an earlier observed action
cannot restore those versions. The experiment reuses `finite_journal.py`.
It does not move merge decisions into the plugin or add a second algorithm.

Concurrent edits retain both versions, even when their clocks say 1970 and 2099.
A delete concurrent with a previously unseen edit retains both the deletion
witness and edit as an unresolved conflict. That edit is not an equal-identity
retry. No clock winner or new product conflict policy was selected.

History events use distinct stable record identities. Two old-dated events
remain independently available in the model. Explicitly deleting one removes
its live version without deleting the other. The transport retains earlier
immutable actions. This proves logical deletion, not forensic erasure of old
payloads, SQLite free pages, logs, or backups.

Physical deletion clears one object's live payload and permanently retires
its identifier. Delayed uploads return 410, including after restart. A delete
before upload prevents that upload too. Upload/delete races cannot restore
the identifier. A retired identifier cannot be reused for unrelated records.

Do not physically delete arbitrary journal actions to implement history deletion.
Missing actions can block causal dependencies. This experiment does not collect
its journal. Production collection needs a durable equivalent summary and
deletion protection, as the finite-checkpoint report already requires.

The local prototype persists actions before upload. A raw socket uploads an
action and reads none of its response. An independent connection witnesses the
committed action before the socket closes. The local action survives that lost
acknowledgment and a database reopen. Retrying finds the original object, then
permits local acknowledgment. No duplicate object remains.

A 410 rejection retains the pending action and raises an explicit error.
Flushing through Bob's account fails before upload. A changed payload with
an existing local action identity also fails. Missing earlier journal actions
remain waiting across restart and do not advance accepted Bookfin coverage.
Arrival of the missing action then permits both to apply.

## Evidence and measured costs

The release build reports zero warnings and zero errors. The final experiment
passes 21 tests: five local tests and 16 actual-server tests. The evidence records
the exact duration. Five server starts cover initial startup, three clean
restarts, and restart after one forced stop. Clean exits report 0; the forced
stop reports -9. The plugin remains Active after those exercises.

| Account | Retained objects | Deletion markers | Live payload bytes, UTF-8 | Greatest sequence |
| --- | ---: | ---: | ---: | ---: |
| Administrator | 0 | 0 | 0 | 0 |
| Alice | 103 | 5 | 68,266 | 105 |
| Bob | 5 | 3 | 12 | 8 |

The database measures 110,592 bytes after shutdown, including indexes and unused
pages. This excludes logs and the local pending-action database. Counts include
the deliberate 65,536-byte object, race tests, and model samples. They are not
typical-user storage estimates or a throughput benchmark.

Committed evidence retains meaningful red phases: six storage tests received
501 from unimplemented routes; three local tests found absent durability or
scope checks; the upload test found no missing-acknowledgment failure; and the
null-character test received 500 instead of 201. These behaviors pass finally.
Concurrent local account claims also exposed a database-lock failure. An atomic
scope claim now permits one account and rejects all others without losing actions.
An intermediate restart also caught a plugin initialization bug that disabled
the plugin. The final suite explicitly verifies its Active status.

The earlier research regression suite passes all 40 tests. The full project
command `nix develop --command bash tool/bookfin test` also passes, including
the SDK-link shell tests and all 271 Flutter tests. These checks ran serially.
No coverage or mutation jobs ran.

## Limits and cleanup

The plugin has no expiry timestamps, retention timer, history pruning,
device retirement, or pending-action discard. Old-dated records survive this
finite experiment. Finite tests do not prove infinite durability.

Retained history and journal operations grow with actions. Physical deletion
leaves one permanent marker per retired identifier. This experiment does not
compress those markers or prove a bound relative to current records and retained
replicas. Disk exhaustion, admission limits, and hostile loads are not measured.
An error never authorizes success, expiry, or silent pending-action loss.

The journal sample uses exactly the two prior research replica identities.
That is not a product device cap. It is a Python model over actual server-stored
actions, not two Android installations or integrated Flutter sync.

Production work remains under boo-3oq0 and the release gate:

- Integrate the dedicated API with the real record and pending-action stores.
- Qualify packaging, installation, account lifecycle, schema migration,
  version compatibility, backup/restore, and operator recovery.
- Prove safe collection or document retained growth without weakening deletion
  protection or indefinite offline-action recovery.
- Surface rejected pending actions and genuine conflicts without silent loss.
- Test failure timing, disk failures, larger loads, and client interruption.

Only Jellyfin 12.4.0 and this plugin build were exercised. Earlier playlist
upgrade evidence does not prove plugin upgrade compatibility. No upgrade,
rollback, power loss, transaction-interruption timing, production installation,
device, browser, coverage, or mutation job was run here.

The fixture is stopped. Ports 7464 and 7465 have no listeners. Private state
remains under ignored `.cache/plugin/run-*/`. Recorded directory mode is 0700;
account files, password files, and storage database are 0600. No secret value
is committed. The orchestrator owns review, integration, and ticket closure.

## Parent review corrections

Review of `179f25a` found two defects. Both reproduced before correction. A leading-null payload uploaded successfully but returned HTTP 500 after restart with invariant checking enabled. Two coordinated connections also both accepted different payloads for the same local action identity.

The invariant checker now uses the same nonempty UTF-8 byte condition as the schema. The payload test restarts the real server and reads the acknowledged payload after the startup checker runs. Local insertion now obtains the SQLite write lock before checking an identity. The two-connection regression holds the first read while the second writer begins; exactly one payload succeeds and the conflicting call fails explicitly. Reopening retains the accepted pending action.

The corrected release build has zero warnings and errors. All 21 dedicated-storage tests pass in a fresh disposable fixture. The updated evidence includes both meaningful failures, corrected source and DLL hashes, five starts, and complete cleanup. These results retain the original scope: no production integration, upgrade, power-loss, disk-full or lifetime-bound claim. Earlier Flutter checks describe the builder base; this research-only correction does not change the app.
