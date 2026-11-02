# Bookfin-owned private playlist protocol: decision evidence

Later decision, November 2, 2026: ordinary playlists are not the selected
production storage surface. The user requires dedicated storage and history
retained until explicit deletion. See `jellyfin-dedicated-storage.md` for the
bounded plugin proof. This report preserves the earlier protocol evidence.

Research ticket: t3-7fv1, under boo-p58t. Baseline: e62257c, including
environment integration 1e6ac01. Measurements ran on November 1, 2026 in
America/New_York; evidence uses November 2 UTC timestamps. This is a new
synthetic fixture in t3-b22c5e06, not the retained t3-360b5172 fixture.

## Result and recommendation

November 2 continuation: `jellyfin-finite-checkpoint.md` now records one tested
checkpoint candidate, batched costs, and the pinned 12.3.0 to 12.4.0 exercise.
It also records exact deleted-record and missing-sequence growth blockers.
Production sync remains gated. The initial observations and proof plan below
remain historical evidence, not the current list of unperformed experiments.

The exact payload confidentiality gap is resolved. After storing a payload,
Alice receives 200 and the exact payload from `GET /Items/{id}`. Bob receives
404 from the same route for the same object, with no payload in the response.
The earlier `GET /Playlists/{id}` denial is not used as a substitute.

Independent private objects remain a viable storage primitive. Caller operation
identifiers can deduplicate a real lost-acknowledgment retry at the logical
operation level. This is stronger than the previous naive-create result.
It is not a complete sync protocol.

There is a concrete storage-surface blocker if coexistence means that ordinary
playlist management must not overwrite, remove, or publish Bookfin records:
owner rename overwrites the stored payload, owner deletion removes the object,
and an explicit owner public toggle lets Bob read the payload. All three use
ordinary playlist permissions. Disabling content deletion does not protect the
object. Bookfin ownership is a naming convention, not an app-only permission.
No journal algorithm can recover the only surviving server copy after it and
all redundant copies have been removed through those same owner permissions.
Local copies may help recovery, but cannot guarantee it for a fresh device.

That rejects a claim of an unconditionally protected playlist-only protocol.
It does not prove that every existing-storage protocol is impossible, or that
users cannot accept clearly identified app-data playlists. Normal library scan
and clean restart preserve the tested private payload. Merely browsing a playlist
list was not shown to destroy state. Real Jellyfin UI execution was not performed.

Recommendation: do not approve a production transport yet. Use the finite
two-device continuation report before requesting product decisions. Do not install a
production plugin. A plugin's dedicated namespace could address playlist
management exposure, but its lower total implementation/maintenance risk has
not been measured. A plugin also needs a retention and offline-recovery policy.

## Terms and one coherent candidate

An operation is one durable Bookfin action, such as creating a bookmark or
deleting it. An operation identifier is a caller-generated identifier retained
across retries. A physical object is a Jellyfin playlist. A logical operation is
the action after equal identifiers and equal payloads have been combined.
A replica is one app installation with durable local records and pending actions.
A tombstone is retained knowledge that a record was deleted. A checkpoint is a
durable summary of accepted operations and the record state they produced.
Compaction replaces older operations with a checkpoint and removes redundant
physical objects. A deletion fence is information that prevents an old operation
from restoring a deleted record after compaction.

The candidate is one immutable operation journal, stored as private objects that
Bookfin creates. Immutable means Bookfin never changes a published payload; it
does not mean Jellyfin prevents the owner or another authorized client changing it.
All bookmarks, deletions, history actions, membership acknowledgments, and
checkpoints would use that same journal. Do not use another client's documents.

Candidate publication and recovery, not an accepted implementation:

1. Persist each action and its operation identifier locally before any upload.
   A production envelope would include a schema version, replica identity,
   durable replica sequence number, causal context, and payload digest. Causal
   context identifies operations that the author had already observed.
2. Create a short private staging playlist. Publish the complete serialized
   payload by updating its name. Accept only a complete validated envelope.
   Staging objects are discoverable before publication, so they cannot count as
   accepted operations. Large create and large update are not interchangeable.
3. On a lost create response, discover and publish matching staging objects or
   retry. Equal operation identifiers with equal payloads represent one action.
   Conflicting payloads with one identifier must report corruption, not choose
   whichever object happens to be listed last.
4. Merge accepted immutable operations, not device snapshots. Keep independent
   actions and preserve conflicting versions until the conflict policy resolves
   them. A concurrent deletion and edit must not become an accidental resurrection.
5. Retain deletion fences and accepted operation knowledge when deleting duplicate
   objects or compacting. A delayed create can succeed after physical cleanup.
   Before collecting old history, prove that checkpoints cover the removed work
   and that stale publications cannot bypass the retained fences.

The research decoder proves only equal-ID deduplication, preservation of
independent operations, exclusion of staging/unrelated names, and rejection of
conflicting duplicate payloads. It does not implement causal merging, current
record conflict resolution, checkpoint publication, membership, or compaction.
Its small envelope is a fixture, not the proposed production schema.

## Runtime evidence

The JSON files named below are under `tool/research/sync/evidence/`. They contain
statuses and synthetic measurements, not passwords, tokens, or private payloads.

| Requirement | Actual evidence | Meaning and boundary |
| --- | --- | --- |
| Same-route privacy | `playlist-confidentiality.json`: owner 200 with exact stored name; Bob 404, 162 response bytes, no payload | Resolves the review gap for this private object and this build; not an audit of every route or an administrator |
| Authentication and owner write | `playlist-objects.json`: anonymous item GET 401; Bob playlist update 404 | Ordinary-user isolation for the measured routes |
| Lost acknowledgment | A real create is independently witnessed; its connection closes without reading response bytes; retry creates a second object | Server create is not idempotent; equal caller identifiers reduce two objects to one logical operation |
| Duplicate cleanup | Owner delete returns 204; a delayed create and publication again leave two physical copies of one operation | Cleanup is not a deletion fence; retained operation/checkpoint knowledge is still necessary |
| Publication | A short staging name is visible before the payload update; repeat identical update returns 204 | Validated-envelope publication is plausible, but server-side atomic create of a large operation is not established |
| Conditional update | A deliberately stale `If-Match` still returns 204 | Do not use that header as a checkpoint compare-and-swap operation |
| Independent offline actions | Two distinct prepared operation payloads are both discoverable; prior `playlists.json` also measured independent concurrent creates | No shared-snapshot overwrite is required; same-record conflict handling is not implemented |
| Create size | ASCII names of 240 bytes succeed with 200; 256, 1,024, and 65,536 bytes return 500 | Create is constrained by filesystem name handling on this host; these samples do not establish the exact maximum |
| Update size | Serialized payloads of 65,613 and 262,221 bytes return 204 and read back exactly | Accepted samples only; no maximum, quota, or safe aggregate size is proved |
| Alternative ordinary metadata | Owner `POST /Items/{id}` with an Overview payload returns 403 and leaves the original name intact | Do not assume a separate writable description field under these ordinary-user permissions |
| Ordinary listing | An unfiltered owner playlist query includes the object and its 199-byte serialized operation name | This is user-facing playlist data, not an invisible app namespace; no UI rendering test was run |
| Rename | Ordinary owner rename returns 204; the old name payload is gone | Bookfin cannot enforce an immutable journal through playlist permissions alone |
| Sharing | Explicit owner public toggle returns 204; Bob then reads the synthetic payload with 200 | Deliberate sharing changes the authorization boundary; it is not a leak while the object remains private |
| Private restoration | Explicit owner private toggle restores Bob's 404 | This separate sharing experiment does not weaken the initial same-route private-object result |
| Delete | Owner deletion returns 204 while content deletion permission is false; owner GET of that same item then returns 404 | That policy is not protection from playlist removal |
| Paging | `playlist-paging.json`: page size two, four objects; deleting the first after page one makes page two omit a still-live object; total changes from four to three; a separate insertion before page two repeats a live object | Offset pages do not form a stable snapshot during mutation; a fresh scan after writes stop finds the remaining objects |
| Library scan | `playlist-scan.json`: a newly completed RefreshLibrary task is witnessed; owner exact read 200, Bob 404 | Normal full library scan preserves the selected payload; not every metadata-replacement or third-party cleanup mode |
| Restart | `playlist-protocol-restart.json`: same server identity, existing ordinary tokens, exact payload, owner 200 and Bob 404 after clean stop/start | Same pinned binary only; no process-kill, power-loss, backup-restore, or upgrade claim |

The sharing experiment deliberately exposes only a synthetic note to the second
synthetic account, then restores privacy. No production credentials, records,
server routes, or other client's storage were accessed. No File request was used.
The existing CustomPrefs and Enhanced snapshot experiments were not rerun.

## Initial gaps before the finite continuation

The table records the first fixture's scope. The continuation report supersedes
its untested checkpoint, batching, and specified-upgrade entries; it does not
claim a complete production protocol or a lifetime storage bound.

| Area | Necessary rule | Status |
| --- | --- | --- |
| Discovery during mutation | An accepted scan must not miss work that cleanup then removes; deletions must wait for covered checkpoints/acknowledgments | One-pass offset scanning is concretely disproved; eventual repeated scans after quiescence work, but do not authorize concurrent compaction |
| Concurrent checkpoint writers | A checkpoint must not supersede unknown accepted operations; concurrent summaries need a proven merge/coverage relation | Not implemented or tested; ignored If-Match cannot provide this |
| Deletion after compaction | Keep enough accepted-ID or causal knowledge to reject old operations after tombstones/duplicate objects disappear | Not proved; old create acceptance disproves only deletion-by-removing-objects |
| Sequence-prefix summaries | A per-replica highest accepted contiguous sequence can compress duplicate knowledge only if gaps, local crashes, and identifier reuse are handled | Plausible technique, not a tested protocol; largest observed number is not a safe substitute for a contiguous prefix |
| Long-offline replicas | Define when a replica can be retired and what happens to its old pending actions | Product decision tb-5fyd; indefinite automatic acceptance must not be silently replaced with expiry |
| History retention | Define retained history by age/count and distinguish it from current live bookmarks | Product decision tb-5fyd; no numerical retention limit is selected |
| Conflict semantics | Preserve both positions for genuine conflicts; define delete-versus-concurrent-edit and recovery of retired pending actions | Plan requires preservation, but complete decision and runtime tests remain absent |
| Namespace coexistence | Accept ordinary-playlist management exposure, or require storage outside that management surface | Product decision tb-887c; the exposure is a measured limitation, not a hypothetical plugin benefit |
| Aggregate bounds | Bound pending staging objects, delayed retry duplicates, checkpoint copies, bytes per object, and retained replica knowledge | No demonstrated bound or server quota; safe cleanup cannot be inferred from individual DELETE success |
| Compatibility | Test the chosen protocol across a specified old/new server pair, with immutable artifact hashes and rollback/restart evidence | Only Jellyfin 12.4.0 is run; no upgrade compatibility is claimed |

Publication of a checkpoint is not just publication of JSON. It transfers
authority from the old journal to a summary. Independently immutable playlist
objects avoid overwriting another device's action, but do not by themselves prove
that this transfer is safe. Cooperative client validation might supply the missing
rules. These gaps are unproved, not demonstrated impossibilities.

For example, retaining the highest contiguous accepted sequence for each replica
can reject exact old retries without retaining every deleted record forever.
That is why the naive resurrection experiment is not a proof against all
playlist protocols. Another possible compression rule gives each record a birth
identifier containing its creator's replica identity and sequence. A checkpoint
that covers that birth but has no live entry can represent deletion without a
separate tombstone for every old record. This also needs a proven join between
concurrent checkpoints, gap handling, and an explicit policy for later edits to
that deleted birth identifier. It is not implemented by the fixture.

A previously unseen higher-numbered action from an offline replica may depend
on old state. Its admission after deletion-fence collection still needs
causal/membership rules. Retiring a replica and forgetting its identity without
a persistent generation rule merely recreates that problem. These are reasons
to prove the complete protocol, not to assert that a summary is impossible.

## Product question 1: ordinary-playlist management

| Design | What the user gets | Cost |
| --- | --- | --- |
| A: Explicit Bookfin app-data playlists | No new server plugin; ordinary private playlist primitives | Serialized payload names remain in the playlist surface; rename/share/delete can alter Bookfin data; user must accept that restriction and recovery limits |
| B: A separate per-user record namespace | Bookfin records are not ordinary playlist entries | A suitable existing namespace has not been proved; the accepted small-plugin fallback requires development, compatibility testing, installation, and maintenance |

Example A: creating a bookmark eventually creates or extends a clearly identified
app-data playlist. Example B: creating that bookmark writes a dedicated per-user
record with no playlist entry. Both keep local offline operation and normal
Jellyfin progress reporting. Both need privacy and the same sync semantics.

Parent question: may ordinary playlist management also manage Bookfin's backing
records, or must Bookfin records remain separate? This is not settled here.

Clutter must be assessed for the best coherent candidate, not only a strawman.
One object per event creates one playlist per event. Sealed immutable batches and
checkpoint objects can reduce that count without changing the journal model.
They do not hide the serialized name, remove the owner management permissions, or
prove bounded cleanup. This research did not run a Jellyfin web/mobile UI or a
large-history usability/performance test, so it cannot quantify a user's tolerance.
Calling either the resulting clutter reasonable or all playlist protocols
unreasonable would be a product judgment not established by the measurements.

## Product question 2: retention and stale replica admission

A growth bound here means a bound on retained history and protocol overhead
relative to current user data and admitted replicas. It cannot mean constant total
bytes while allowing infinitely many live bookmarks. A server plugin needs the
same definition.

| Design | Offline guarantee | Cost to bounded cleanup |
| --- | --- | --- |
| A: Retain every paired replica until explicit recovery/revocation | A device may remain offline indefinitely without automatic retirement | Causal stability can wait indefinitely; deletion/history knowledge or replica summaries must remain, and unfinished checkpoints cannot justify deletion |
| B: Retire replicas under an approved expiry or revocation rule | A retired device first rejoins and reconciles; old pending work is kept for explicit recovery rather than silently replayed | User must choose expiry/revocation and recovery semantics; protocol needs durable generation/fence checks and must demonstrate that delayed old publications are ignored |

Example A: a device reconnecting years later still receives the retained deletion
knowledge before uploading. Example B: the device's pending old actions remain
locally recoverable, but cannot automatically restore server-deleted records.
Both keep a durable local pending-action record and forbid silent loss or silent
resurrection. Neither design or any expiry duration is selected. History's own
age/count retention is also still a user decision.

Parent question: must every paired device retain automatic upload rights forever,
or may an approved retirement rule require explicit recovery of its pending work?
Selecting B does not by itself prove the playlist checkpoint protocol; selecting
A does not imply every safe protocol has unbounded tombstones per record.

## Reproduction, source evidence, and final environment

Run the commands in `tool/research/sync/README.md`, under its pinned Nix shell.
`playlist_protocol.py` is a measurement fixture, not a production Bookfin transport.
Its confidentiality observer has six red-then-green HTTP tests that reject
two denied reads, an incorrect owner payload, a successful other-user read, or
a denied response containing the raw or JSON-escaped payload. The discovery decoder has behavior
tests for retries, independent actions, incomplete/unrelated objects, and
conflicting duplicate payloads. The clean decoder red run has three assertion
failures, not import/reference errors. An intermediate test-file placement mistake
caused three attribute errors; it was fixed before that clean red run and is not
counted as red evidence. An exploratory insertion probe also assumed that a
numeric suffix would sort before alphabetic suffixes; that assumption failed.
The corrected probe verifies its insertion order explicitly before measuring
the repeated item. That failed assumption is not a Jellyfin sync failure.
All 20 research tests pass after the change.
No application behavior changed, so no Flutter build/test was run in this task.
No coverage or mutation job was started.

Source was fetched from the immutable Jellyfin commit in `sources.json` and
verified against its recorded SHA-256. The source archive is ignored under
`.cache/sync/source/`; no other checkout's credentials or state were copied.

| Source path at 83d0d0e7f76e23e2e085c8ff67d28b772d35967d | Relevant lines | What it explains |
| --- | --- | --- |
| Jellyfin.Api/Controllers/UserLibraryController.cs | 82, 97 | Exact item payload route and user-filtered lookup |
| Jellyfin.Api/Controllers/PlaylistsController.cs | 121, 141 | Owner/share edit permission and update dispatch |
| Jellyfin.Api/Models/PlaylistDtos/UpdatePlaylistDto.cs | 13 | Nullable fields preserve unspecified properties; no separate description payload |
| Emby.Server.Implementations/Playlists/PlaylistManager.cs | 80, 130, 184 | Name-derived directory, distinct suffix on repeated creates |
| Emby.Server.Implementations/Playlists/PlaylistManager.cs | 604, 622, 665 | Full name replacement and repository update, no caller revision argument |
| MediaBrowser.Controller/Playlists/Playlist.cs | 118 | Playlist deletion authorization differs from generic content-deletion policy |
| Jellyfin.Api/Controllers/ItemUpdateController.cs | 33, 72 | Generic metadata update requires elevated permissions |

The source supports the measured behavior; it is not a replacement for the
runtime evidence. Update-size acceptance is host/build-specific, and future
server behavior cannot be inferred from this one archive.

The server is cleanly stopped after the restart measurement. Port 7364 has no
listener. Private synthetic state remains restartable in this worktree's
`.cache/sync/runtime/`, with generated account files mode 0600 and the directory
mode 0700. The prior research fixture remains untouched. No production plugin was
installed, no machine service was changed, and no global toolchain was installed.
No device or browser was used.


## Parent correction and next engineering proof

The privacy observer now searches all decoded JSON strings, including nested
values and object keys, for the private payload. A denied response containing
JSON-escaped text must not pass merely because it uses a field other than Name.
The new regression failed for detail, nested detail, and array responses before
the correction. All 21 research tests now pass through the pinned research shell.
This corrects the observer; no new Jellyfin runtime capture was performed.

The product questions above gate production sync, not reversible research or
listening implementation. Use two fixed device identities, no automatic expiry,
and preservation of unresolved conflicts as explicit research conditions. These
conditions do not select product limits or discard pending user actions.

Complete one bounded candidate proof:

1. Check checkpoint coverage and concurrent merging with a missing earlier
   operation and a delayed retry.
2. Delete a bookmark, replace old operation objects with checkpoints, and verify
   that delayed operations cannot restore the deleted bookmark.
3. Measure immutable batches, checkpoint counts, stored bytes, and discovery work
   for a stated workload. Quantify playlist clutter before asking tb-887c.
4. Test one specified pinned server-version pair before any upgrade claim.

If this candidate fails, report the concrete failure and compare its user-visible
costs with the accepted plugin fallback. Do not search every imaginable protocol.
Exact device caps, retirement durations, or history limits are not prerequisites
for these tests. Ask about them only where measured alternatives require a
user-visible tradeoff. No plugin or production transport is selected.
