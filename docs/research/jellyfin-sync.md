# Disposable Jellyfin sync and permission evidence

Research date: November 1, 2026, America/New_York. Some evidence timestamps are
November 2 in UTC. Base: `2817cf3`. Ticket: `ta-qobz`. This supplies evidence to
`boo-p58t` and `boo-2cgp`; the parent owns acceptance and closure.

## Result and decision boundary

A snapshot is a complete document saved in one request. An acknowledgment is the
response that confirms a write. An operation identifier names one user action
across retries. A record revision names one accepted version of one record.

The disposable server runs official Jellyfin 12.4.0 and official Enhanced
12.14.0.0 binaries. Ordinary-user permissions, byte ranges, chapters, standard
playback reporting, and restart persistence work in the measured cases.
Shared CustomPrefs snapshots and Enhanced bookmark documents fail the required
concurrency and deletion behavior. Enhanced incremental additions also duplicate
an action after a lost acknowledgment.

These failures do not reject every existing-storage protocol. Private playlists
provide a distinct, app-owned, discoverable storage primitive. A storage primitive
is a server capability, not a complete sync protocol. Ordinary owners
can create, update, and delete these objects without administrative permission.
This research did not complete a safe journal protocol over those objects.
Do not report that a plugin is logically necessary, or close the storage gate.

A small plugin remains an engineering fallback hypothesis, not a measured lower-risk result or a selected transport. A plugin can own record identifiers, accepted revisions,
and deletion history in one transaction. That is an engineering recommendation,
not evidence that an unimplemented plugin already meets the requirements.
The user chose existing storage first: prove or concretely reject the private
playlist protocol before selecting a transport. Ticket `t3-7fv1` records that remaining work.

## Environment, isolation, and provenance

The reproducible commands are in `tool/research/sync/README.md`.
The dedicated flake pins nixpkgs at
`fe13242281a67641c0102cdb1087f0ebe586c7df`. Its native server and plugin
archives have fixed content hashes. It unpacks official binaries rather than
starting a large source build. The .NET runtime is bundled with Jellyfin.
The Nix shell limits .NET to two logical processors. FFmpeg generation is serial.

All server directories belong to this checkout's `.cache/sync/runtime/`.
The listener was inspected as `127.0.0.1:7364`, not a wildcard address.
Discovery, UPnP, IPv6, and remote access are disabled. The production server,
production accounts, and preview servers were not accessed or changed.
No browser or device tools ran. No shared machine service was modified.

One fixture administrator performs setup. Alice and Bob are ordinary users.
Alice can access both synthetic books libraries. Bob can access only the public
books library. Both initially have explicit download permission.
Passwords are generated locally. Passwords and tokens remain only in ignored,
private files. Committed evidence includes no authentication headers or secrets.

The immutable source and artifact identities are in `sources.json`.
The local runtime evidence is in `evidence/provenance.json`.
A DLL is a compiled .NET library.

| Artifact | Measured identity | What it does not establish |
| --- | --- | --- |
| Jellyfin native archive | Official macOS ARM64 v12.4 archive; runtime reports 12.4.0 | An independently reproduced build from the inspected source |
| Jellyfin source | Tag v12.4 points to `83d0d0e7f76e23e2e085c8ff67d28b772d35967d` | A cryptographic build attestation for the native archive |
| Enhanced archive | Official Jellyfin-12 archive; SHA-256 `cbedb0f98a1827fb9d943372aa986260bb2244e95672c16e5b27a524fa321d43` | Equality with the remote production plugin binary |
| Enhanced DLL | SHA-256 `adca0f59a4271ad7c7549439b19c350f37302211fcb724b2bfa36358e5883564`; embedded informational-version string names `9bbf16c0de6662baeaa23e51c71505c15c560381` | A reproducible build with every build-time override accounted for |
| Enhanced runtime | Plugin status Active; plugin list and version endpoint report 12.14.0.0 | Removal of the source's version discrepancy: project and manifest still say 12.13.0.0 |
| Enhanced frontend | Both served asset hashes match the immutable tag and d327f68's earlier observations | Identity of the production backend DLL |

The reference checkout at `d327f68` was read directly, including its report from
line 425 and sanitized evidence. It was not merged or modified. The parent owns
its pending download guard and documentation corrections.

## Ordinary-user catalog and media results

`evidence/catalog.json` records the requests and selected returned fields.
`evidence/catalog-dtos.json` preserves bounded server responses for application
integration tests. Only path prefixes are rewritten. The DTOs, the response
objects that describe items, contain synthetic identifiers rather than secrets.

| Check | Actual result | Interpretation |
| --- | --- | --- |
| No credentials: catalog or Download | 401 | Authentication is required |
| Bob lists items | Four audio files; hidden synthetic audio absent | Library filtering applies to this ordinary user |
| Bob fetches hidden item or its Download | 404 | Knowing the item identifier does not grant access |
| Alice requests a nonexistent item or Download | 404 | Missing content is not downloadable |
| Bob sets Alice's user ID in a catalog request | 403 | The query cannot impersonate another ordinary account |
| Alice downloads bytes 0–31 and 32–63 | 206; Content-Range matches file length; bytes match the seeded file | Two independent range requests return the expected source bytes |
| Administrator disables Alice's download permission | Alice's current policy says false; raw Download request returns 403 | Server enforcement does not depend on the research client's guard |
| Policy omits download permission | Unit test blocks before HTTP | This is client evidence; this server always returns the permission field |
| Denied Download | No File requests occur | File is never used to bypass the denial |
| EPUB Download | 206; bytes match the seeded EPUB | The ordinary user can acquire this source format |
| Synthetic playback reports | Alice retains 600,000,000 ticks; Bob retains zero | Per-user standard resume writes work for the selected source item |

A tick is 100 nanoseconds of recorded audio. Alice's measured resume position is
60 seconds. The synthetic audio lasts only three minutes. Default Jellyfin
audiobook resume thresholds are five minutes at each end. The first playback
experiment therefore returned zero, not the desired 60-second position.
For the measured positive playback experiment, only the disposable instance's
`MinAudiobookResume` and `MaxAudiobookResume` settings were temporarily set to
zero minutes, then restored. Changing the generic minimum duration did not solve
the audiobook-specific rule. Do not hide this fixture adjustment or interpret
the first zero position as a transport failure.

This is API playback reporting, not proof that a real Android player emitted the
reports. It does not prove exact historical activity backfill, background audio,
network policy, whole-edition acquisition, or interrupted-download recovery.

## Actual ordering and pairing evidence

The synthetic work has two recordings and one EPUB. Recording A contains three
files whose alphabetical names deliberately disagree with track order.
Jellyfin returns all three as separate AudioBook items, each with one media
source. It does not return one audio item containing three ordered sources.

| Returned file name | Disc number | Track number | File order requested from Jellyfin |
| --- | --- | --- | --- |
| z-first | 1 | 1 | 1 |
| a-second | 1 | 2 | 2 |
| m-third | 2 | 1 | 3 |

The query sorts by `ParentIndexNumber,IndexNumber` in ascending order. The first
field is the returned disc number; the second is the returned track number.
The returned names and numbers are asserted, not inferred from seeded filenames.
The first file also returns two embedded chapters at zero and 90 seconds.

The recording-A folder, the separate recording-B item, and the EPUB share the
same returned work ancestor. Single-file directory resolution collapses the
recording-B and text directories; recording A remains a folder. This asymmetry
matters: matching only immediate parents misses recording A or picks recording B
as the sole audio edition. Matching title alone also fails because the audio
items' titles are track labels, while the common work title is their album.

The report checks the returned ancestor relationships and keeps the two audio
editions distinct. It also downloads the EPUB by its returned item identifier.
The expected grouping in `catalog-dtos.json` is an authored fixture relationship,
not an inferred server pairing. The application catalog mapper did not run in
this checkout. The parent must feed these real responses through the catalog
mapper and assert the grouping before closing boo-2cgp. Seeded files alone do not
prove application mapping, and this report does not claim otherwise.

## Existing storage: measured counterexamples

A preference scope means one user, one item-like identifier, and one client
string. A tombstone
means a retained record that says another record was deleted.
The evidence is in `evidence/storage.json`.

### Core CustomPrefs

Two clients read the same empty scope. One saves record A. The other saves record
B from its old snapshot. B survives; A disappears. A later retry of the first
snapshot removes B. Clearing the scope and replaying the old snapshot restores
A. These are real requests against the disposable server, not a persistence
model. A deliberately stale `If-Match` header still returns 204. This route does
not provide the conditional update that the header would request.

Different scopes do coexist, and another ordinary user cannot fetch or write
Alice's scope by passing her user ID. That is useful isolation. It does not fix
discovery of new device or record scopes: the served OpenAPI exposes only the
single-scope DisplayPreferences route, not arbitrary-scope enumeration.

GET of one fresh scope creates one DisplayPreferences row and one
ItemDisplayPreferences row. Posting an empty document leaves both rows. The
public route offers no corresponding deletion operation. An immutable record per
scope would therefore need a discovery mechanism and a justified growth bound;
the shared-snapshot counterexample alone does not refute that different design.
A 65,536-byte custom string round-trips. This is an observed accepted size, not a
maximum supported size or a retention guarantee.

### Enhanced documents and additions

The arbitrary `bookfin.json` route returns 404. Unknown top-level fields in
bookmark and settings documents do not survive typed serialization. There is no
proven independent Bookfin document namespace here. Do not hide Bookfin records
inside `syncedFrom`, another client's labels, or another client's typed records.

An actual POST is sent over a socket. Another connection witnesses its committed
bookmark. The first connection closes without reading any response bytes. The
same addition is then retried. Two bookmarks remain, with different server-made
identifiers. The server cannot recognize one user action from the duplicate
payload alone. Independent concurrent additions fare better: all eight additions
from two workers remain. This confirms that incremental add is not equivalent to
a shared snapshot.

The existing web client's save protocol still sends the complete bookmark
document. Replaying an earlier document removes another incremental addition.
Deleting a bookmark returns 200, repeating that delete returns 404, and replaying
the earlier document restores the deleted bookmark. No tombstone remains after
deletion. This source-matched client request pattern is tested through HTTP;
the web client itself was not opened or executed.

A 65,536-byte bookmark label round-trips despite the frontend's smaller input
limit. This does not establish a backend maximum, safe growth, retention, or
transfer cost for a real history. Cross-user GET, full save, addition, and deletion
all return 403. Missing authentication returns 401.

### Reads that create storage

`evidence/read-side-effects.json` measures an untouched synthetic user's
documents. The test removes only an empty synthetic directory before the first
request; it does not remove a populated user document.

| Request | Directory | bookmark.json | settings.json |
| --- | --- | --- | --- |
| Before either GET | Absent | Absent | Absent |
| GET bookmark.json | Created | Absent | Absent |
| GET settings.json | Present | Absent | Created with defaults |

A settings GET is not a read-only storage probe. An empty bookmark GET creates a
directory but does not write the bookmark document in this build.
The earlier storage phase also records repeated reads of populated Alice
documents. Use the separate fresh-user phase for first-read side effects.

## A distinct existing-storage candidate: owned private playlists

Follow-up: [the complete-protocol assessment](jellyfin-playlist-protocol.md)
resolves the same-route payload privacy gap on a fresh fixture and measures
lost-ack logical deduplication, concurrent-mutation paging, owner management
exposure, library scan, and clean restart. It records concrete limitations and
unsettled retention/coexistence decisions, not approval of a complete transport.
The original observations below remain scoped to the earlier fixture.

The evidence is in `evidence/playlists.json`. This candidate uses objects that
Bookfin would create and own, not reserved fields in someone else's records.

Alice creates an empty private playlist with an explicit `IsPublic=false` flag.
She discovers it through the item listing, changes its name to a serialized
payload larger than 65 KiB, and reads that payload back. Two concurrent creations
with different names both remain. Bob's GET /Playlists/{id}, POST /Playlists/{id},
and DELETE /Items/{id} return 404. Bob does not discover the object in listing.
Bob's direct GET /Items/{id}, the route used by Alice to retrieve the payload,
was not tested in that earlier phase. The t3-7fv1 follow-up now measures owner
200 with the exact payload and Bob 404 without the payload on the same
`GET /Items/{id}` route and object; see `playlist-confidentiality.json` and the
linked assessment. Alice can delete her own object even
when content-deletion permission is disabled. Ordinary-user permissions therefore
do not justify rejecting this candidate.

Repeating a create request returns a distinct object. Deleting that object and
repeating the create makes the logical operation visible again. Those observations
reject a naive create/delete protocol, not an immutable operation journal with
operation identifiers and retained deletion knowledge. A journal is a sequence
of user operations from which current records can be reconstructed.

One coherent direction is one immutable private object per operation, with an
operation identifier in its app-owned payload. Discovery lists only the owner's
private objects. Clients deduplicate by operation identifier and merge accepted
operations rather than replacing another writer's snapshot. This is a research
direction, not an implemented or validated transport. The complete protocol still
needs evidence for paging during writes, conditional publication or safe partial
objects, existing-client changes, retry cleanup, and upgrade behavior. Clean
restart of the private object itself passes, but not a complete journal protocol.
Paging means retrieving a list in separate bounded responses. Publication means
making a complete operation visible to other Bookfin replicas.

Deletion knowledge must survive stale replicas, devices with an older local copy.
If tombstones are removed while such a replica can upload old state, deletions
can reappear. Finite growth therefore needs a stated retention or replica-expiry
rule, followed by a rule that rejects expired writes. Neither an unbounded set of
playlist operations nor silently discarding old offline actions meets that gate.
No such rule is selected or proven in this investigation. A plugin needs an
explicit retention rule too; its existence does not solve this by itself.

### Designs for the parent to compare

| Design | What the user gets | Cost and unresolved proof |
| --- | --- | --- |
| A: App-owned private playlist journal | No new server plugin; discoverable private objects and independent operation ownership | Playlist objects appear in normal Jellyfin storage; client-side publication, merge, cleanup, paging, and retention need proof |
| B: Small plugin with per-user records | A dedicated record namespace; one owner for accepted revisions, operation deduplication, and change discovery | Another plugin to install and maintain; all promised behavior still needs implementation and runtime tests |

Example A: an offline bookmark becomes one privately discoverable operation;
retrying that action must converge to one logical bookmark even if two playlist
objects were created. Example B: the same action supplies its operation identifier
to one plugin transaction; a retry returns the original accepted result.

Both designs need authenticated per-user ownership, durable local pending work,
an explicit conflict policy, retained deletion knowledge, bounded requests,
retention rules, compatibility checks, and recovery after a lost response.
The parent's unresolved choice is the installation cost of design B versus the
additional protocol and playlist-exposure cost of design A. This research does
not choose on the user's behalf.

## Restart durability and remaining limits

The restart phase uses an authenticated clean shutdown, waits for process exit,
then starts the same pinned binary with the same isolated directories. It checks
the same server identity, ordinary-user tokens, the 65,536-byte CustomPrefs value,
the Enhanced bookmark label, the private playlist payload, and Alice's standard
playback position. Every check passes in `evidence/restart.json`. The final
authenticated shutdown completes, the process exits, and no listener remains on
port 7364. The isolated data remains available for the parent.

Two launch mistakes occurred before the successful clean-restart measurement.
An early readiness script indexed a startup response that had no Version field.
A background job without redirected input was suspended by the terminal. Its
shutdown did not finish promptly; only that verified disposable process was
eventually force-stopped. Starting another copy before its exit produced
`Failed to bind to address http://127.0.0.1:7364: address already in use.`
The final harness adds a tested readiness predicate, avoids unnecessary TLS
certificate loading for its HTTP-only client, and documents redirected input for
background launch. Recovery after the forced stop passed too. The retained
restart evidence was then rerun after a separate authenticated clean shutdown,
not mislabeled from the forced-stop attempt. No other process was stopped.

Clean restart persistence is narrower than power-loss durability. No process-kill
timing, filesystem failure, device sleep, backup restore, or server upgrade was
tested. No maximum request size, storage quota, time-based retention, deleted
replica recovery, or long-running load limit is established. Logs and evidence
are bounded by this short investigation, not a production retention service.

The live production DLL has not been fetched or compared. Local official-release
behavior is not proof of byte-identical deployed backend behavior. Source
observations, earlier deployed observations, and this disposable runtime evidence
must remain distinct.

### Acceptance matrix

“Pass” below describes only the measured case, not an accepted production
transport.

| Required proof | Core CustomPrefs snapshots | Enhanced documents/additions | App-owned private playlist primitive |
| --- | --- | --- | --- |
| Authentication and ordinary-user isolation | Pass | Pass for reads, saves, add, and delete | Follow-up: same item payload route returns owner 200 and Bob 404 without payload |
| Independent ownership and existing-client coexistence | A separate client scope exists; shared-scope writers still replace each other | No independent Bookfin document; existing client's full save can remove new entries | Follow-up: own objects survive scan, but owner rename/delete/share can alter or expose state |
| Discovery | Only a known scope; arbitrary-scope enumeration absent in served API | Whole typed document is discoverable | Follow-up: mutation between offset pages skips a live object; fresh scan after quiescence finds it |
| Concurrent independent edits | Lost edit reproduced | Eight independent additions survive; stale full save still loses one | Independent objects survive; complete merge/publication protocol unproved |
| Retry after lost response | Stale retry overwrites later edit | Duplicate fresh identifiers reproduced after an unread response | Follow-up: real unread create acknowledgment yields two objects but one logical operation ID; cleanup fencing unproved |
| Deletion without resurrection | Stale snapshot restores deletion | Stale full save restores deletion | Naive delete/create restores an operation; deletion fencing unproved |
| Limits, bounded growth, and retention | 65,536-byte value accepted; cleared scopes retain rows; upper bounds and retention unproved | 65,536-byte label accepted; quota and retention unproved | Payload above 65 KiB accepted; object-growth bound and retention unproved |
| Restart durability | Pass for clean restart | Pass for clean restart | Pass for clean restart of payload |
| Compatibility and provenance | Pinned local official binary and inspected source; production equivalence unproved | Local archive, DLL hash, embedded source commit, and asset hashes recorded; production DLL unresolved | Local Jellyfin 12.4.0 only; upgrade and other-client compatibility unproved |

No column establishes a complete accepted protocol. In particular, the last
column preserves a possible existing-storage path rather than using failures in
the first two columns as a proof of impossibility.

## Source paths and reproduction

`tool/research/sync/sources.json` records immutable archive URLs and hashes.
The following source paths are relative to the recorded commits, not a moving
branch. Commands in the README run all behavior through pinned Nix shells.

| Repository | Source path | Evidence used |
| --- | --- | --- |
| jellyfin/jellyfin | Jellyfin.Api/Controllers/DisplayPreferencesController.cs | Scope mapping, reserved preference keys, full replacement calls |
| jellyfin/jellyfin | Jellyfin.Server.Implementations/Users/DisplayPreferencesManager.cs | Exact scope filtering, GET creation, transactional set replacement |
| jellyfin/jellyfin | Jellyfin.Api/Controllers/LibraryController.cs | Download policy, user-filtered item lookup, range-enabled file response |
| jellyfin/jellyfin | Jellyfin.Server.Implementations/Security/AuthorizationContext.cs | Modern token in Authorization; legacy token header is optional |
| jellyfin/jellyfin | Emby.Server.Implementations/Library/UserDataManager.cs | Audiobook-specific resume thresholds |
| jellyfin/jellyfin | Emby.Server.Implementations/Library/Resolvers/Audio/AudioResolver.cs | Separate audio items and directory resolution |
| jellyfin/jellyfin | Emby.Server.Implementations/Library/Resolvers/Books/BookResolver.cs | Single-ebook directory resolution |
| jellyfin/jellyfin | Jellyfin.Api/Controllers/PlaylistsController.cs | Ordinary creation, ownership checks, owner updates |
| jellyfin/jellyfin | Emby.Server.Implementations/Playlists/PlaylistManager.cs | Server-generated object identity and full-name update |
| jellyfin/jellyfin | MediaBrowser.Controller/Playlists/Playlist.cs | Private visibility and owner deletion |
| n00bcodr/Jellyfin-Enhanced | Jellyfin.Plugin.JellyfinEnhanced/Controllers/JellyfinEnhancedController.cs | Typed documents, defaults, fresh-ID additions, deletion |
| n00bcodr/Jellyfin-Enhanced | Jellyfin.Plugin.JellyfinEnhanced/Configuration/UserConfigurationManager.cs | Per-user directory creation and serialized file updates |
| n00bcodr/Jellyfin-Enhanced | Jellyfin.Plugin.JellyfinEnhanced/Configuration/UserConfiguration.cs | Fixed bookmark and settings types |
| n00bcodr/Jellyfin-Enhanced | Jellyfin.Plugin.JellyfinEnhanced/js/enhanced/bookmarks/bookmarks.js | Existing client's full-document saves and cleanup |
| n00bcodr/Jellyfin-Enhanced | Jellyfin.Plugin.JellyfinEnhanced/js/enhanced/config.js | Existing client's complete-document HTTP save queue |

The four core safety behaviors first failed with 14 assertion failures, without
import or syntax errors. A later modern-authentication test failed because the
token was absent from Authorization. A later transfer test failed because missing
permission still started HTTP. Each was corrected and rerun. Additional tests
protect redirect refusal, no File fallback, and private credential output.
A readiness test also failed on a startup document without server identity, then
passed after the guard was implemented. All ten research-client tests pass.
The repository's Flutter suite also passes all 34 tests with
`nix develop --command flutter test --concurrency=1 --reporter expanded`.
No coverage or mutation-testing job was started. The parent coordinates that
work after user acceptance.
