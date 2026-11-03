# Production personal-record sync candidate

Ticket: boo-3oq0. Candidate measured on November 2, 2026.
This integrates Flutter record owners with the dedicated authenticated object
API proved in `jellyfin-dedicated-storage.md`. It is not the earlier Python
outbox proof, an ordinary playlist, or a released server plugin.

## Setup and compatibility

The app needs the compatible Bookfin Storage plugin on its Jellyfin server for
personal-record sync. Standard Jellyfin progress reporting remains separate.
Without the plugin, local reading, listening, bookmarks, and history remain
available. The app retains pending records and reports that sync did not finish;
it never tries custom preferences or playlists instead.

The candidate plugin source remains under `tool/research/plugin/`. Its current
name and description explicitly identify it as a research candidate. It is
tested only against the pinned disposable Jellyfin 12.4.0 in this repository.
Do not install this candidate on a live server. Deployment packaging, supported
server versions, backups, upgrades, and release approval are tracked by
t6-il6y. The app does not claim that a production plugin release exists.

## State ownership and invariants

`LocalResumeStore` owns one serialized record state per account. Audio and
reading use views of this owner, not independent databases. The account key
includes the server origin/path, server identity, and authenticated user.
Android uses SQLite with write-ahead logging and `synchronous=FULL`. Each
transaction stores records and their pending upload actions together. Legacy
preference data is copied into SQLite without deleting the legacy copy. A
SQLite failure never switches Android back to preference writes.

The preference-backed constructor remains available for existing host tests
and non-Android previews. Preference writes do not establish Android durability.
`RecordDatabase.checkInvariants()` checks SQLite integrity on demand.

`RecordJournal` retains immutable actions identified by installation and positive
sequence number. Each action carries its account and causal context: the
sequence numbers the installation had accepted. A wall clock never selects a
winner. Actions with missing causal predecessors wait across restart. An
acknowledgment removes a pending upload only after the returned identifier,
payload, deletion flag, and positive sequence match the request.

The journal invariants checked by `checkInvariants()` are:

- Every pending upload names a retained action.
- Accepted record versions are covered by accepted installation sequences.
- Each retained record has at least one version; discovery cursors are nonnegative.
- Action guards enforce immutable identities, account scope, valid record
  addresses, and valid causal contexts before accepting external actions.

Discovery applies and saves each ordered page before saving its cursor in the
same transaction. Retired action objects, malformed records, nonadvancing
cursors, and exhausted request budgets fail explicitly. No journal collection
or physical action deletion occurs in this candidate.

## Merging and choices

Independent bookmarks and history actions merge by stable record identity.
Audio and reading positions stay separate. Audio resume identity covers the
whole recording's source list, not the current track. Changed source revisions
remain different records. A stale reader or player snapshot changes only the
records that its owner changed; it cannot delete newly discovered records.

Concurrent resume versions are not automatically selected. Ongoing position
saves explicitly retain the other installations' conflicting versions. The
account sheet lists the choices. Choosing creates bookmarks for both resume
positions before resolving the resume record. It does not seek the active
audio decoder or move the active reading page. Concurrent bookmark edits and
deletion witnesses also remain available as choices. Deletion is logical: old
immutable journal payloads and server backups are not forensic erasure.

The `preserve` field names observed versions that an ordinary continued save
must not resolve. It extends the opaque Bookfin journal payload, not the plugin
API. Causal predecessors still arrive before an action can apply. Explicit
choices clear preservation. This prevents a normal playback tick from silently
resolving a conflict that the user has not chosen.

History has no automatic expiry. The history view now provides explicit deletion
of one action. Bookmarks and other history actions remain unchanged.

## Verification and limits

Run host checks through `nix develop --command bash tool/bookfin test` and
`nix develop --command flutter analyze`. Run the real server test with
`nix develop ./tool/research/sync --command python3 tool/sync_fixture.py`.
The runner checks availability of its own loopback ports 7464 and 7465, starts a
fresh server and ordinary accounts, uses two separate real SQLite client files,
and stops its own server in a finally block. Ports 7364/7365 and devices are not
used. Credentials stay in ignored mode-0600 files.

The actual-plugin test covers offline bookmarks, retained old history, reading
versus audio records, clock differences, deletion, client database reopening,
conflicting resume positions, explicit choice, and retry idempotency. Separate
HTTP tests cover unverified acknowledgments, wrong authenticated accounts,
stale owner snapshots, ordered pages, and malformed remote records. Earlier
proof evidence remains unchanged.

Android runtime and two-device acceptance remain open. SQLite close/reopen and
acknowledgment retry are not a power-loss or disk-full proof. Journal actions
currently grow without collection, including superseded resume saves. t6-t9po
blocks release hardening until a durable equivalent checkpoint or safe unsent
resume representation is established. No lifetime storage or speed bound is
claimed. Coverage and mutation testing remain parent-owned after acceptance.

## Independent review corrections

The original `ccff7dc` candidate is not approved for integration. The correction
boundary starts after the safe reader milestone `94457bf`. Review findings F1–F4
have separate controlled regressions, rather than a claim that static traces
were observed on Android.

An owner accepts a persisted snapshot only after its account and local record
revision still match and all records decode successfully. `ResumeStore.read`
does not change the store's accepted-record baseline. Playback and ReaderSession
explicitly call `acceptSnapshot` at that accepted transition. A held refresh
rejected after a local change cannot authorize deletion of a remote bookmark.
Successful writes advance the same domain baseline to the owner's saved
snapshot, not to every record merged from the journal. Records the owner has
never accepted remain outside its deletion authority. An unpersisted pending
snapshot restored after account switching does not advance that baseline.

Playback tracks the last decoder address recorded locally, separately from the
resume selected by synchronization. A flush waits for existing writes and
retries pending writes. It creates a position update only after the decoder
address changes. Choosing either a local or remote resume therefore does not
move paused audio or let an unchanged decoder overwrite the choice. A later
real decoder sample can update the selected resume. A choice whose identity is
no longer current returns a recoverable message and reloads current choices.

Persisted journal containers, action containers, pending identities, discovery
cursors, and pending-to-action references are checked before casts or internal
invariant checks. Invalid saved data raises `FormatException`, remains intact,
and does not poison the reader's write queue. Pending snapshots and unsynced
actions survive storage failures and later storage recovery. Internal invariant
failures are not converted to storage recovery.

Conflict headings and choices use the current catalog's book title, edition
label, and source name. Audio choices show file-relative time, including
milliseconds when needed to distinguish nearby places. Reading choices show a
saved quotation and source page when available, not raw anchors or identifiers.
Saved audio record labels provide a fallback for books outside the current
library. Missing books, missing sources, changed sources, and unavailable
reading previews are explicitly identified.

The correction regressions include actual coordinator/player choices in both
directions, delayed audio and reader refresh races, retry after damaged journal
data is restored, pending account switches, and widget descriptions. Their HTTP
fixtures use authenticated loopback transport on kernel-assigned ports. This
does not replace actual-plugin integration or Android acceptance.

Release gates remain unchanged: `t6-t9po` must address retained-journal growth
and full parse/rewrite work during ordinary once-per-second playback saves and
acknowledgments. No save-latency measurement or bound is claimed. `t6-il6y` must
validate production plugin packaging, deployment, and upgrades. No fallback to
ordinary Jellyfin playlists exists.
