# Jellyfin feasibility evidence

Ticket: `boo-p58t`. Local research date: November 1, 2026, America/New_York.
Authenticated captures use November 2 UTC. These are the same local research evening.
Continuation base: integrated main `31953f9`.
Initial research base: `a6bfc1cc82b1ce8dc1705fee5408d868a9dfb6a1`.
Scope: supported Jellyfin APIs, bounded authenticated inspection, extension source, and a disposable local model.
No application implementation, plugin installation, or server configuration changed.
No metadata-modification or playback-reporting endpoint was called.

An API is the server's application interface. OpenAPI is its machine-readable description.
A UUID is a generated unique identifier. A namespace reserves names for one client's records.
One KiB is 1,024 bytes. One MiB is 1,048,576 bytes.

## Result and recommendation

The user's server reports `12.4.0`, not the previously inspected 10.11.0.
Both its public information endpoint and its served API description report this version.
Public GET requests succeeded. Protected GET requests returned 401 without credentials.
The supplied private login now works. It belongs to an administrator with download permission.
One visible books library contains 1,485 `AudioBook` entries and zero indexed `Book` entries.
Eight 64-byte reads of actual MP3 and M4B files returned valid 206 partial responses through the reverse proxy.
The files exposed 21 and four chapter starts respectively, all present, nonnegative, and ordered.
Their item user data was unchanged between reads.
Ordinary-user access and isolation remain unproven. No storage-test or playback-reporting write ran.

Keep ordinary Jellyfin APIs for catalog access, original-file downloads, and playback reporting.
Do not promise complete personal-record sync through `CustomPrefs`.
`CustomPrefs` is Jellyfin's dictionary of custom display-preference strings.
The matching upstream source replaces that dictionary without a caller-supplied version check.
It exposes no public operation to list arbitrary preference scopes.
These omissions leave the proposed shared-snapshot protocol without a demonstrated solution for concurrent edits, device discovery, and durable deletions. They do not prove that every possible protocol using existing server capabilities is unsuitable.

The small-plugin fallback remains a candidate, not a demonstrated necessity.
The installed Jellyfin Enhanced version is `12.14.0.0`, reported as active.
Its deployed bookmark JavaScript exactly matches the inspected release-tag source.
That client still writes whole bookmark snapshots, including delete-all and orphan cleanup.
The extension's add/delete APIs improve individual mutations but do not expose an isolated Bookfin record store.
Do not use another client's shared bookmark/settings documents for a live write experiment.
Before selecting a plugin, finish the extension/protocol decision gate and disposable integration tests below.
This research does not claim that the user's server lost real data.
Catalog and small audio-download interfaces are usable with the supplied account.
Complete edition grouping, ebook pairing, ordinary-user permissions, and personal-record sync remain open.
Keep this ticket in progress.
Do not implement the plugin in this research ticket or silently reduce the promised sync behavior.

## Evidence classes

| Evidence class | What actually ran | What it establishes | What it does not establish |
| --- | --- | --- | --- |
| Live public HTTP | Public info, served OpenAPI, four protected GET requests without a token | Reported version, advertised route shapes, authentication barrier | Installed build commit, ordinary-user authorization, actual library organization |
| Live authenticated HTTP | Password login, current-user policy, visible book catalog, MP3/M4B items and siblings, playback-info GET, eight small media GETs, installed-plugin list, session logout | Actual administrator-visible catalog counts, chapter/source availability, observed range behavior, Enhanced version/status | Ordinary-user access/isolation, complete work/edition mapping, ebook bytes, progress-write effects, storage sync |
| Live extension asset comparison | Public Enhanced version, synthetic-user unauthenticated bookmark GET, deployed bookmark/config JavaScript SHA-256 | Version endpoint agrees with installed-plugin list; bookmark authentication barrier; byte-for-byte match of two frontend source files | Exact backend DLL provenance, ordinary-user isolation, storage-write behavior or durability |
| Upstream source inference | Release tag `v12.4`, commit `83d0d0e7f76e23e2e085c8ff67d28b772d35967d` | Expected implementation for a matching unmodified release | That the target binary exactly matches that commit or every deployment setting |
| Local HTTP fixture | Dart HTTP server with synthetic responses | Probe safety, namespace separation, response filtering, retry and deletion behavior against the fixture | Real Jellyfin persistence or permission enforcement |
| Local whole-set model | File-backed replacement operations with forced stale-read schedules | Counterexamples for protocols that rely only on whole-set replacement | Jellyfin transaction isolation, real concurrent request outcomes, proxy limits, server restart durability |

The upstream release API identifies tag `v12.4`, published October 26, 2026.
There is no `v12.4.0` tag at the checked ref endpoint. The server's version string remains `12.4.0`.
Do not substitute 10.11 behavior without checking the newer source.

## Reproduce the safe evidence

The tools use the existing Nix development shell. They add no dependencies.
Run each command separately. Do not run competing build or hardening jobs.

```sh
nix develop --command flutter test tool/research/jellyfin --reporter expanded
nix develop --command dart analyze tool/research/jellyfin
nix develop --command dart run tool/research/jellyfin/probe.dart https://jellyfin.example.com
nix develop --command dart run tool/research/jellyfin/whole_set_fixture.dart
```

The committed `public-evidence.json` contains selected public fields only.
The committed `authenticated-evidence.json` contains sanitized administrator observations only.
It excludes titles, paths, account/item/source identifiers, credentials, tokens, and media bytes.
The committed `local-evidence.json` contains synthetic fixture results only.
The whole-set model creates a temporary directory, reopens its JSON file for each operation, and deletes that directory afterward.
It does not launch Jellyfin or restart a process.

To repeat the authentication barrier checks, discard response bodies:

```sh
for endpoint in Users/Me UserViews 'Items?Limit=0' \
  'DisplayPreferences/bookfin-public-check?client=BookfinPublicInfo'; do
  curl --max-time 20 --silent --show-error --output /dev/null \
    --write-out "$endpoint %{http_code}\n" "https://jellyfin.example.com/$endpoint"
done
```

All four returned 401 on November 1, 2026. No authenticated preference scope was created by those requests.
The raw public OpenAPI download had SHA-256
`283b7f68f011653446056d5ae25ac1cad306bfc034f4352d5345e07614a896a1`.
The probe stores selected routes, not the full schema or installed-plugin route list.

## Catalog discovery and media mapping

A book is the user's conceptual work. An edition is a recording or text of that work.
A file is one physical downloadable part. A chapter is a named range inside a recording.
Do not collapse those four things into one Jellyfin item.

Use `GET /Users/Me` to identify the authenticated user and inspect ordinary-user permissions.
Use `GET /UserViews`, not the administrative library configuration API, to find visible libraries.
Select `CollectionType=books`. The checked enum has `books`, not a separate `audiobooks` value.
Do not classify libraries by their names. A user can name a music library "Audiobooks".

Within each selected view, query `GET /Items` with its `ParentId`, `Recursive=true`,
`IncludeItemTypes=AudioBook,Book,Audio`, and requested fields such as
`Chapters,MediaSources,ProviderIds,ParentId,CanDownload,SortName`.
Page through all results before asserting that a book has no other parts or ebook editions.
The safe probe samples at most three book views and thirty items per view.
Its sample is not a full inventory and cannot prove absence.

| Jellyfin fact | Expected meaning and reliability | Bookfin treatment |
| --- | --- | --- |
| `Id` | Item identifier within this server; not a work or edition identifier | Preserve as a source reference, scoped to server and account |
| `Type=AudioBook` | Audio resolved inside a books library; supports resume and played status | Treat a playable item as a candidate recording part, not automatically a whole edition |
| `Type=Audio` | General audio; resolver can use this in mixed or music libraries | Do not import all music as books; ask for an explicit correction when relevant |
| `Type=Book` | Recognized ebook item, possibly represented by a directory containing one supported ebook | Treat as a candidate text edition; inspect its actual file/source |
| `ParentId` | Catalog hierarchy, not a guaranteed edition relationship | Grouping evidence only; a folder can hold several works or formats |
| `MediaSources[].Id` | Source/version identifier for one item; not a file ordering list | Retain it with the item reference; use playback info to choose a playable source |
| `IndexNumber`, `ParentIndexNumber` | Integer track/disc information for audio, or parsed book indexes; may be absent or wrong | Ordering evidence, not an invented canonical order |
| `Chapters[].StartPositionTicks` | Chapter start within this file's recorded timeline, in 100-nanosecond units | Keep file reference and start; derive end from next start or known file duration |
| `RunTimeTicks` | Reported duration in 100-nanosecond units; nullable and dependent on probing | Do not manufacture exact whole-edition time if any preceding duration is unknown |
| `ProviderIds` | Provider-specific identifiers with differing scopes and metadata quality | Candidate matching evidence; do not equate ISBNs for different formats or silently merge titles |
| `SeriesId`, `SeriesName` | Source series association or parsed/folder-derived metadata | Preserve provenance; Bookfin owns confirmed ordering, including fractional entries |
| `UserData.Key` | Internal user-data key; audio source derives keys partly from metadata | Not a durable Bookfin identity; use item references for reporting |
| `Path`, source `ETag`, source `Size` | Optional source facts, not a global identifier or guaranteed HTTP validator | Keep private; verify the actual HTTP response when resuming a download |

The audio resolver does not provide a general, reliable multi-part audiobook container.
Its multi-item path skips grouped results with several files and leaves multi-part support unresolved.
The file resolver can still expose individual `AudioBook` items.
Authenticated inspection now confirms exposed audiobook items and embedded chapters.
The inspected sample has no provider identifiers or track indexes, and does not establish a multi-file edition.
Do not assume that one folder, one item, or `MediaSourceCount` means one complete recording.

For a confirmed multi-file edition, prefer the explicit Bookfin file order.
Otherwise propose an order from complete disc/track metadata within a confirmed grouping.
Natural filename order is only a candidate when metadata is missing.
Repeated track numbers, missing discs, and ambiguous filenames need confirmation, not an invisible tie-break.
The current research does not implement this ordering policy.

The audio prober requests embedded chapters for `AudioBook` and saves extracted chapter data.
It also derives track and disc indexes from audio metadata.
Missing chapter data is not proof that a file contains only one logical chapter.
A file boundary can be used as a navigation boundary, but must not be relabeled as an extracted chapter.

### Actual catalog and download observations

The final capture began at `2026-11-02T00:27:41.554903Z`, November 1 in America/New_York.
Its account was administrative, not an ordinary test account.
The final command completed session logout without error.
It issued 28 HTTP requests: two session POSTs, 18 metadata GETs, and eight media GETs.
No progress report, storage-test write, account creation, or server change was requested.
Downloads may create download-activity entries. Standard item GETs can perform source-defined on-demand refreshes.
The probe did not request a metadata refresh or modify metadata through an update endpoint.

| Visible catalog quantity | Observation | Scope and limit |
| --- | --- | --- |
| Books libraries | 1 | Current account's `CollectionType=books` views |
| `AudioBook` entries | 1,485 total; 30 sampled | Server-reported filtered count; not 1,485 confirmed works or editions |
| Sample containers | 22 MP3 and eight M4B | First 30 audiobook entries only; derived from media sources when top-level container is absent |
| Embedded chapters | 27 of 30 sampled items | Missing chapter data does not establish chapter absence in the file |
| Track indexes/provider IDs | Neither present in the 30-item sample | No trustworthy multi-file order or cross-format matching established |
| Multiple media sources | None in the 30-item sample | Multiple files in an edition are not the same thing as multiple media sources on one item |
| `Audio` entries | 0 | Recursive filtered count in the selected books view |
| `Book` entries | 0 | No indexed ebook pair available in this view; physical sidecars elsewhere remain unknown |
| `Folder` entries | 5 | Recursive filtered count; hierarchy alone does not identify a work or edition |

| Representative file | Source availability | Chapter starts | Small original-file reads | Observed item user data |
| --- | --- | --- | --- | --- |
| MP3 | One source in item details and playback-info GET | 21, all nonnegative and ordered | `/File` and `/Download`, bytes 0–63 and 64–127, each 206 with 64 bytes and matching `Content-Range` | Present and unchanged before/after |
| M4B | One source in item details and playback-info GET | Four, all nonnegative and ordered | Same four successful partial reads | Present and unchanged before/after |

The final capture transferred 512 media bytes in total. It saved no media bytes.
Two earlier read-only inspection runs each transferred four 64-byte MP3 ranges.
Across this continuation, media probes therefore transferred 1,024 bytes in 16 successful partial responses.
Neither a complete download nor interruption/resume recovery was tested.
The account policy allowed downloads and playback. Permission denial for an ordinary account remains untested.
Read-only playback-info GET returned sources, and item GET returned `UserData`.
No `/Sessions/Playing`, `/Sessions/Playing/Progress`, or `/Sessions/Playing/Stopped` request ran.
The source-defined progress semantics remain in the progress section; live progress-write effects remain unproven.

For acquisition, the served schema advertises item-ID-based `/File` and `/Download` routes.
The inspected book/file/download/attachment route subset exposes no named HTML/Markdown acquisition endpoint.
The Book resolver source still excludes those formats. No HTML, Markdown, EPUB, MOBI, or PDF bytes were acquired.
This is not evidence that unindexed sidecar files do not exist on disk.
Keep `td-4nvl` open and do not replace server-backed acquisition with local import without a user decision.

## Concrete identity boundary for later implementation

Keep Bookfin's local identifiers independent from mutable Jellyfin metadata.
This follows the approved book/edition/file model; it does not add a second competing model.
The accompanying `jellyfin-identity.html` diagram shows the proposed ownership boundary.

| Stored object | Concrete identity or reference | Behavior when source facts change |
| --- | --- | --- |
| Account scope | Canonical configured server origin, observed Jellyfin server instance ID, authenticated user ID | Do not combine records across users or replacement server instances; require explicit relinking |
| Book | Bookfin-generated UUID within the account scope | Keep confirmed grouping when title, author, or source folder changes |
| Edition | Bookfin-generated UUID, book UUID, audio-or-text kind | Own its resume position and confirmed file order independently of other editions |
| File | Bookfin-generated UUID, edition UUID; source reference includes server instance ID, Jellyfin item ID, and chosen media source ID when present | Preserve local records; require relinking if the source disappears or changes identity |
| Downloaded asset | File UUID plus observed source revision facts and verified response size/validator where available | Invalidate or revalidate changed bytes; never append a new source to an old partial download |
| Chapter | File UUID plus imported chapter start in source ticks, with import provenance | Refresh imported chapter lists without moving user bookmarks silently |
| Bookmark/history position | Edition UUID, file UUID, recorded-audio position in milliseconds | Retain old source references during relinking; never use whole-book percentage as identity |

One millisecond equals 10,000 Jellyfin ticks.
Bookfin stores recorded-audio time, not time divided by playback speed.
Whole-edition time is the sum of earlier file durations plus the current file position.
Keep unknown duration distinct from zero duration.
An item ID is not promised to survive removal, rescan, path changes, or server replacement.
The actual persistence of source IDs across those operations has not been tested here.

The ebook resolver accepts `.azw`, `.azw3`, `.cb7`, `.cbr`, `.cbt`, `.cbz`, `.epub`, `.mobi`, and `.pdf`.
It does not include `.html` or `.md` in that extension list.
Those approved reader formats therefore need an explicit import/discovery plan if this server does not expose them.
Follow-up ticket `td-4nvl` records this newly found acquisition gap for the parent.
Do not promise them through Jellyfin catalog discovery alone.
The resolver can represent a directory as a book when it contains exactly one recognized ebook.
Several formats can become separate items instead of a single multi-format edition.

There is no inspected standard field that explicitly pairs an audiobook edition with its ebook edition.
Shared parent folder, title, author, ISBN, and provider identifiers are evidence, not a guaranteed relationship.
Show candidates for confirmation. Store confirmed pairing as a Bookfin record.
No real pairing or supported-format sample from this user's library has been inspected.

## Downloads, permissions, and byte ranges

Use `GET /Items/{itemId}/Download` for an original file, after checking item access and download permission.
The source applies the Download authorization policy, checks `CanDownload(user)`, and returns a physical-file response with range processing enabled.
It also logs a download activity. A future authorized byte probe will therefore create ordinary download activity even if it fetches only one byte.
Do not probe a folder as though it were a downloadable whole-book archive.
Multi-file downloads need one verified transfer per confirmed file.

`GET /Items/{itemId}/File` also returns an original file with range processing in this source.
However, it is marked with ordinary authorization, not the Download policy used by `/Download`.
Do not use that difference to bypass the user's download permissions.
Client policy must remain at least as restrictive as `EnableContentDownloading` and item downloadability.
This is a route distinction from source, not a live permission-bypass finding.

Use playback information for playable sources and server-supported playback methods.
Do not persist a transient transcoding URL as the identity of a downloaded original file.
Do not log token-bearing URLs or the filesystem paths returned in media-source data.

Before claiming resumable downloads, an authorized follow-up must check:

1. A known accessible file returns 206 for `Range: bytes=0-0`, with a correct `Content-Range` and one response byte.
2. A later range and an unsatisfiable range behave correctly through the real reverse proxy.
3. Response validators and `If-Range` prevent joining bytes from different file revisions.
4. A disabled-download ordinary account and an inaccessible item are rejected without falling back to `/File`.

No live file download, HEAD request, byte range, or permission-denial matrix ran.
The probe currently does not automate those media checks.
Original-file ranges are a source-supported candidate, not a verified property of the user's deployment.

## Playback progress and sessions

The supported reporting sequence is `POST /Sessions/Playing`, then
`POST /Sessions/Playing/Progress`, then `POST /Sessions/Playing/Stopped`.
Report the current file's `ItemId`, the chosen `MediaSourceId`, and current file `PositionTicks`.
Preserve the `PlaySessionId` from playback setup when the server supplies one.
The controller obtains the authenticated session itself; it does not trust a caller to select another user's session.

Read `UserData.PlaybackPositionTicks`, `Played`, `PlayCount`, and `LastPlayedDate` for the authenticated item.
The checked user-data writer stores rows by user, item, and custom key.
Audio custom keys can depend on metadata. They are not the identity to use for Bookfin records.
No inspected API field establishes a canonical whole-edition resume position across separate file items.

The server's audiobook resume thresholds can clear positions near the beginning or mark a file played near its end.
Their configured values on this server are unknown.
Keep Bookfin's precise local position and standard Jellyfin progress as related but distinct facts.
Do not treat a returned zero position as proof that a listener intentionally rewound.

Source progress handling updates `LastPlayedDate` using server processing time.
Standard progress calls therefore do not prove accurate backfilling of historical offline listening times.
Keep exact history in Bookfin records. Reconcile offline resume activity before reporting a current position.
Do not upload the entire backlog as though it were a sequence of live sessions.
No playback start/progress/stop call ran on the real server because it would change play state.
Future live validation needs an explicitly designated disposable media item and permission to change that account's play state.

## Display preferences: transport facts

A preference scope is one user, one item-like ID, and one client string.
The controller accepts arbitrary `displayPreferencesId` strings; non-GUID values are mapped to an MD5-derived ID.
The inspected path does not require that this ID identify a real library item.
This gives Bookfin a candidate namespace without modifying library metadata.

Omitting `userId` selects the authenticated user.
The shared helper rejects another user's ID unless the requester is an administrator.
This is source evidence for ordinary-user isolation, not a live two-account test.
Administrator API keys are not suitable test credentials: upstream treats API keys as unrestricted.

The GET operation constructs standard display fields and reserved custom preference keys.
It also creates missing preference rows. A GET is not necessarily storage-neutral after authentication.
The POST operation consumes reserved keys, replaces the remaining custom preference set, then saves other preference objects separately.
Do not use the client names of Jellyfin Web, mobile clients, or production Bookfin for research.

Version 12.4 differs from the old source finding in two material ways:

1. Its custom-set replacement runs inside a database transaction and retries database update failures up to three attempts.
2. Preference creation catches a competing insert and can return the already stored row.

Those measures handle database races. They do not reject a stale application snapshot.
A later successful full-set replacement can still discard keys from an earlier successful replacement.
The overall HTTP operation also updates several preference objects through separate saves, not one demonstrated transaction for the entire request object.

The deletion at the start of S2's replacement is:

```csharp
            dbContext.CustomItemDisplayPreferences.Where(prefs => prefs.UserId.Equals(userId)
                                && prefs.ItemId.Equals(itemId)
                                && prefs.Client == client)
                                .ExecuteDelete();
```

where

- `dbContext` = the database context for this replacement attempt.
- `CustomItemDisplayPreferences` = the stored custom preference rows.
- `Where(...)` = the operation that selects rows satisfying the expression.
- `prefs` = one candidate stored row.
- `UserId`, `ItemId`, and `Client` = the row's user, item-like ID, and client string.
- `userId`, `itemId`, and `client` = the requested preference scope.
- `Equals(...)` = identifier equality.
- `ExecuteDelete()` = deletion of all selected rows inside this replacement transaction.

The subsequent inserts restore only the supplied keys. The transaction does not compare the caller's old revision with current state.

| Required transport property | Checked source/API evidence | Result for full personal-record sync |
| --- | --- | --- |
| Conditional update | No caller version, `If-Match` check, or compare-and-swap operation in the inspected controller/manager | Not provided by this path |
| Record discovery | Public schema exposes GET/POST for a known preference ID, not a list of arbitrary scopes | No demonstrated discovery protocol |
| Per-device discovery | `/Devices` requires elevation; `/Sessions` describes sessions, not a durable inventory of all historical record writers | Not a safe replacement for a record/device registry |
| Key deletion | Replacing a set without a key removes that custom key | Not a durable deletion record by itself |
| Scope deletion | No public DELETE on the inspected preference route | Clearing research keys leaves preference scope rows |
| Size | Custom values are strings; inspected value entity and OpenAPI declare no finite value-size cap; client entity declares 32 characters | Real request, proxy, DB, and practical history limits unmeasured |
| Restart/upgrade durability | Database-backed source, with no live restart or upgrade experiment | Not proven for the deployed server |

An entity's declared string length is not proof of a hard SQLite or proxy limit.
Do not interpret successful 16 KiB local values as a server limit or an unlimited storage guarantee.
The source does not supply a retention or capacity contract for Bookfin history.

The served schema also advertises existing non-core per-user bookmark/settings routes under `JellyfinEnhanced`.
Their advertised bookmark payload is specific to that client's records and contains no declared operation ID or revision.
Only the public version/assets and an unauthenticated synthetic-user bookmark GET were called; no authenticated bookmark/settings document was read or changed.
The extension assessment below establishes the installed version and matching frontend source, but not an isolated general Bookfin record store.
Do not infer that the server has no plugins, or reuse that client's files as Bookfin's disposable namespace.

Assessment of this existing extension is an explicit transport-decision gate. Establish its matching implementation/version, ordinary-user authorization and isolation, storage ownership, safe coexistence with Bookfin records, write/discovery/retry/deletion behavior, and size/retention/persistence/compatibility limits. Obtain authorized disposable integration evidence for any viable candidate. Missing revision fields in the schema alone do not settle its semantics. Do not select a new plugin until this gate is resolved.

## Local counterexamples and safety proof

The HTTP probe has 23 passing behavior tests after this authenticated continuation.
Four whole-set model tests and three existing application tests also pass.
They cover public reads, plaintext credential refusal, redirect refusal, explicit write opt-in,
administrator refusal, missing-policy refusal, research-key restrictions, bounded sizes,
retry, deletion, fresh namespace separation, private-field filtering, and the complete synthetic command path.
The failure-path test also checks that only the disposable scope is identified, with no raw response or token printed.
Both namespaces and all payloads are synthetic.

The whole-set fixture has four passing behavior tests for observed counterexamples and persistence through file reopening.
The initial stub runs failed on expected missing behavior: twelve probe tests, then four fixture tests.
The later failure-diagnostic test also failed before the client identifier was added to safe diagnostics.
The first implemented public-read test passed before the remaining probe behavior was added.
No coverage, mutation, soak, or real-server stress claim is made.

Final broader verification used `flutter test test tool/research/jellyfin --reporter expanded` inside `nix develop`.
All twenty-one tests passed: eighteen research tests and three existing Flutter tests.
Scoped Dart analysis reported no issues. Dart format verification passed.
This run excludes the separate SDK shell test and Android builds.

The deterministic schedules produce these observations:

1. Two devices read the same empty set. Their separately merged writes both succeed in the model. Only the second bookmark remains.
2. Separate per-device partitions retain both payloads. Competing registry updates leave one device undiscoverable.
3. A deletion record, also called a tombstone, replaces a bookmark. Retrying an older full snapshot restores the bookmark and removes the tombstone.
4. Thirty-two stale reads followed by thirty-two serialized writes leave one record and lose thirty-one records in the model.

These are deliberate interleavings, not concurrent HTTP load against Jellyfin.
The model does not emulate database conflicts, transactions, reserved DTO keys, authentication, or actual SQLite constraints.
The independent HTTP fixture tests the probe boundary, not Jellyfin's implementation.
Their success cannot establish real ordinary-user isolation or server durability.

The persistence experiment reopens a file after writes and checks separate synthetic users, items, and clients.
It also checks 1,024-, 4,096-, and 16,384-byte values, identical retries, and removed keys.
This is not a Jellyfin restart, process-kill, disk-failure, or upgrade experiment.

## Two transport designs and their costs

The product plan already chose existing APIs first, with a plugin accepted when needed.
This research compares those same two designs rather than introducing a third transport.

| Design | Installation | What the evidence permits | Unresolved cost |
| --- | --- | --- | --- |
| A: existing server storage | None | `CustomPrefs` settings are plausible; Enhanced source and its deployed bookmark client are now assessed | Shared snapshots and Enhanced-client coexistence remain unsafe assumptions; a safe isolated protocol and ordinary-user integration proof remain open |
| B: small Jellyfin plugin for extra records | One server plugin | Can define the missing per-user record protocol explicitly | Plugin API design, deployment, backups, compatibility, and tests remain work |

Example A: one device writes a synthetic bookmark in its research namespace and reads it back.
That does not establish two-device sync.
Example B: a device submits a bookmark operation with a stable operation ID and an expected record revision.
The plugin accepts it once or returns a conflict; another device can discover the resulting change.
Example B describes required behavior, not an implemented endpoint.

Both designs retain these requirements:

- Local bookmarks, resume positions, grouping corrections, and history work offline.
- Standard Jellyfin catalog and playback behavior stays independent from extra-record transport.
- Records remain inside one server/account scope and never live in shared library metadata.
- The approved cream/sepia UI and feature structure do not change.

The source inadequacy is enough to reject a shared read-merge-write JSON document as a guarantee.
It is not enough to claim that the real server's authentication, capacity, or plugin deployment has been validated.
Keep the accepted plugin fallback provisional. Assess the existing extension and viable existing-storage protocols before concluding that a new server component is needed.
The parent selects the transport only after that decision gate and settles a plugin API separately if needed.

The separate HTML/Markdown acquisition gap has two user-visible choices:

| Design | Example use | Benefit | Cost |
| --- | --- | --- | --- |
| A: explicit local import | Select a Markdown file with Android's file picker | No extra server installation | That file does not come from Jellyfin discovery |
| B: plugin-backed library acquisition | Select an authorized HTML item exposed by a small plugin | Server-backed discovery and download | More server code, permission checks, and deployment maintenance |

Both keep offline reading, edition-specific positions, and active-content restrictions.
Neither is implemented or selected here. The parent must obtain the user's choice rather than silently inventing a source for these formats.

## Existing Enhanced extension assessment

### Deployment and source identity

The public `/JellyfinEnhanced/version` response was `12.14.0.0`.
Authenticated `GET /Plugins` independently reported Enhanced `12.14.0.0`, status `Active`.
The release API identifies tag `12.14.0.0`, published October 26, 2026.
That tag resolves to `n00bcodr/Jellyfin-Enhanced` commit `9bbf16c0de6662baeaa23e51c71505c15c560381`.

The deployed `/JellyfinEnhanced/js/enhanced/bookmarks/bookmarks.js` contains 49,244 bytes.
It exactly matches the same source path at that commit, SHA-256:
`88ed2cb6310234be67ec2e6e9126772d7a1576d1377d61a47deba038fb42b497`.
This is direct deployment evidence for the frontend behavior below, not backend binary attestation.
The deployed `/JellyfinEnhanced/js/enhanced/config.js` also matches the release-tag source exactly.
Its 13,119 bytes have SHA-256 `f12788930e01c1459013b20be4fb1e13df165becf8c79addf13bcad57710c3d2`.
That second file confirms that the save helper posts the supplied document rather than converting it into incremental requests.

The tag's project and manifest still declare `12.13.0.0`.
The release has separate Jellyfin 12 and Jellyfin 10.11 archives.
Its Jellyfin 12 archive's release-metadata SHA-256 is
`cbedb0f98a1827fb9d943372aa986260bb2244e95672c16e5b27a524fa321d43`.
The archive was not downloaded, installed, or compared with the deployed DLL.
Treat backend conclusions as release-tag source evidence until that provenance gap is resolved.
The inspected source targets Jellyfin 12/.NET 10 or Jellyfin 10.11/.NET 9 through separate build targets.
No upgrade, downgrade, restart, or configuration change ran on the real server.

### Authorization, ownership, and protocol

The table distinguishes release-tag backend source from the byte-matched deployed frontend.
An operation ID identifies the same user action across retries.
A deletion marker preserves the fact that a record was removed after its content disappears.

| Requirement | Observed source or live evidence | Remaining proof or limitation |
| --- | --- | --- |
| Authorization | Bookmark/settings routes require authentication. Source permits the same user or an administrator through `UserHelper.GetUserId`. A public GET with an all-zero synthetic user ID returned 401. | No ordinary-user or two-account live test. Administrator success is not isolation evidence. No other real user's records were queried. |
| Storage owner | Fixed per-user `bookmark.json` and `settings.json` files belong to Enhanced under its plugin configuration directory. User-directory names are normalized. | No API accepts a separate Bookfin document or namespace. Do not treat an arbitrary filename or another account as a namespace. |
| Record shape | Typed bookmark fields hold item references, seconds within media, labels, dates, and replacement-edition references. Settings are a typed Enhanced settings object. | No general Bookfin history, grouping, ebook-anchor, or operation schema is advertised. Unknown fields are not a demonstrated persistence protocol. |
| Add operation | Server generates a new bookmark ID and uses a strict read-modify-write under a per-user/file process lock. | No caller operation ID or retry deduplication. A lost acknowledgment can produce another bookmark on retry. |
| Full replacement | Bookmark POST saves the supplied whole document. Settings POST saves changed whole typed settings. | No expected revision check. Full bookmark replacement does not take the add/delete read-modify-write lock. Another client can overwrite an acknowledged add. |
| Discovery | Bookmark GET returns the full typed dictionary; caching is disabled at the controller. | No bookmark pagination, change cursor, conditional update, or operation listing appears in these routes. No live bookmark document was fetched. |
| Delete operation | Source removes the dictionary entry under the same process lock; missing entry returns 404. | No retained deletion marker. A later stale full-document save can restore the removed entry. Repeated deletes need client interpretation of 404. |
| Coexistence | The byte-matched deployed frontend saves whole `bookmark.json` snapshots, exposes delete-all, and offers orphan cleanup. `syncedFrom` already identifies the media item copied from. | A Bookfin marker in `syncedFrom`, label, or ID is not storage isolation. Orphan cleanup can remove synthetic non-media references. Never test this against existing documents. |
| Limits and retention | Inspected bookmark routes impose no explicit record-count or label/request-size limits. The web label input has a 100-character UI limit. Deletes remove content rather than preserving history. | Proxy/runtime limits, storage growth, retention, and full-document download cost remain unmeasured. A UI limit is not a server limit. |
| Persistence | Source writes a random temporary file and renames it over the per-user JSON file. | No explicit disk flush appears in that save path. No real restart, power-loss, backup/restore, or upgrade proof. File-backed persistence is not equivalent to durable acknowledgment. |

The source's add operation generates the ID as follows:

```csharp
            var bookmarkId = $"Bm_{DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()}_{Guid.NewGuid().ToString("N").Substring(0, 9)}";
```

where

- `bookmarkId` = the server-generated key for this request's bookmark.
- `DateTimeOffset.UtcNow` = server wall-clock time for this request.
- `ToUnixTimeMilliseconds()` = milliseconds since January 1, 1970 UTC.
- `Guid.NewGuid()` = a fresh generated identifier, not a caller-supplied operation ID.
- `ToString("N").Substring(0, 9)` = the first nine hexadecimal characters of that generated identifier.

The deployed frontend's add/edit/delete paths use the same whole-document save call:

```javascript
        await JE.saveUserSettings('bookmark.json', owner.bookmark, { throwOnError: true });
```

where

- `JE.saveUserSettings` = Enhanced's operation that posts one complete user settings document.
- `owner.bookmark` = the document retained by that web client's current account session.
- `throwOnError` = whether the caller receives a failed-save error instead of silent failure.

The matched save helper makes this request:

```javascript
                await ApiClient.ajax({
                    type: 'POST',
                    url: ApiClient.getUrl(`/JellyfinEnhanced/user-settings/${userId}/${fileName}`),
                    data: serialized,
                    contentType: 'application/json'
                });
```

where

- `ApiClient.ajax` = the Jellyfin web client's HTTP request operation.
- `ApiClient.getUrl` = the operation that combines a server-relative path with the current server address.
- `userId` = the web client's current account identifier, used privately in the request path.
- `fileName` = the settings document name, such as `bookmark.json`.
- `serialized` = the complete supplied document encoded as JSON before it enters the web client's save queue.

The queue orders writes within that web session. It does not coordinate another device's snapshots.

No Enhanced storage write ran. The supplied account is administrative, and no isolated Bookfin storage namespace was established.
No bookmark/settings GET ran either: settings GET can seed defaults, and bookmark reads can create the per-user directory.
Do not bypass the ordinary-user write guard to fill this evidence gap.

### Transport decision gate

The existing Enhanced routes are assessed, not ignored. Their incremental add/delete routes are better than a shared snapshot alone.
However, they are not currently proven suitable for the promised complete Bookfin record sync.
The deployed client's whole-document saves and cleanup prevent claiming independent Bookfin storage ownership.
This does not reject every protocol over existing server capabilities.
An isolated append/discovery protocol, if proposed, still needs coexistence, retry, deletion, and bounded-growth proof.
Neither shared snapshots nor success against a local HTTP fixture supplies that proof.

Keep the small-plugin fallback provisional. No new plugin or user-visible acquisition design is selected.
Use `ta-qobz` to provide a disposable matching server with two ordinary accounts and synthetic media.
Keep transport concurrency, deletion, retry, limits, retention, persistence, and compatibility proof in `boo-p58t`.
Keep the transport implementation in `boo-3oq0`, after the parent records the selected transport.
The catalog/download evidence can support `boo-u3cg` and `boo-7o92` independently of that selection; the parent owns dependency changes.

## Conflict semantics required by later implementation

An operation ID identifies one user action across retries.
A record revision identifies the accepted version of one record.
A change cursor identifies a position in the server's ordered list of accepted changes.
These values solve different problems; do not substitute a device clock timestamp for any of them.

The extra-record transport needs:

1. Stable record IDs and operation IDs, with atomic retry deduplication and durable acknowledgment.
2. Conditional replacement or atomic append, so an old snapshot cannot erase a newer acknowledged operation.
3. Discoverable records or changes without requiring a client to guess every past device ID.
4. Explicit deletion records, retained until a documented acknowledgment or expiry rule makes removal safe.
5. A full-resync rule for devices that return after deletion records have expired.
6. Explicit record/request limits, pagination, retention, backup, and supported schema versions.

An identical immediate retry is not the same guarantee as retrying an old operation after another device changes the record.
Keep both sides of conflicting resume positions, seek history, or grouping corrections until resolution.
An intentional rewind is valid. Never choose the greatest audio time or an untrusted wall-clock timestamp as the automatic winner.
New edits after reinstall must not pretend to be the lost installation's old writer unless its identity and sequence were recovered safely.

## Authenticated follow-up and safety limits

Use the supplied T3 private login file for authorized read-only investigation.
The earlier token request timed out; the later username/password login succeeded.
Do not request another credential file while the supplied one remains usable.
The probe accepts a login file or an existing session-token file, never both.

```sh
nix develop --command dart run tool/research/jellyfin/probe.dart \
  https://jellyfin.example.com --secret-file /PRIVATE/T3/TOKEN_FILE
```

For the authorized login-file inspection:

```sh
nix develop --command dart run tool/research/jellyfin/probe.dart \
  https://jellyfin.example.com --login-file /PRIVATE/T3/LOGIN_JSON --inspect-media
```

The default authenticated mode reads the current user's policy and bounded catalog samples.
`--login-file` accepts the private `Username`/`Pw` JSON file instead of a pre-issued token.
It authenticates once, keeps the token in memory, and attempts session logout during cleanup.
The login's password and returned token never enter command arguments, reports, or committed files.
The supplied file remains owned by T3's private secret input, not this repository.
The probe uses both the client-identification header and its token field; a token-free `Authorization` header can override `X-Emby-Token` and cause 401.
An initial attempt exposed that header interaction. Its logout also returned 401.
That initial research session may remain registered, although its token was discarded from process memory.
The subsequent successful investigations completed logout without error. No session/device deletion was attempted.
The parent should account for that possible stale research session rather than claiming every server session was revoked.

Read-only mode permits an administrator session and labels ordinary-user isolation unproven.
Storage-write mode still requires a verified ordinary-user session; its independent operation-level guard remains in place.
No administrator storage-write override was added.
Do not request another production account or create one merely to bypass this boundary.
Use a disposable matching test installation for the remaining write and cross-account checks.
The private path above is a placeholder, not a secret value or a file to create in the repo.
Do not paste tokens into command arguments, terminal output, tickets, fixtures, or screenshots.

Only after authorization for disposable preference writes, add `--allow-disposable-write`.
The probe requires an explicitly non-administrator policy before writing.
Each run creates a fresh random `bookfin-research-...` preference ID and a `BookfinResearch-...` client of 32 characters.
The caller cannot supply an existing client or item ID for writes.
It preserves returned defaults, writes only `bookfin.` research keys, and never supplies another user's ID.
It refuses redirects and remote plaintext HTTP to avoid forwarding credentials.

The optional write mode tries values of 1,024, 4,096, and 16,384 UTF-8 bytes.
It repeats each identical write, verifies exact readback, removes research keys in a `finally` cleanup, and verifies their absence.
It leaves the new preference scope rows because no supported scope-delete operation was found.
A failed cleanup can leave synthetic values; inspect the printed research namespace only, never another client's settings.
The command prints both disposable scope identifiers before starting writes, including when later writes or cleanup fail.
On failure the probe suppresses private response content; it does not promise recovery after process kill.
The probe's 16 KiB value, 32 KiB custom-set, 64 KiB preference request, and 4 MiB metadata-response ceilings are client safety limits only.
The metadata-response ceiling now also applies to error bodies. File probes instead cap each response body at 64 bytes.
Each request also has a total 20-second deadline across connection opening, headers, and body receipt. Expiry forcibly closes its own client without disabling later cleanup requests. A real loopback HTTP test keeps sending small body chunks past the deadline and verifies both failure and peer-observed disconnection.

The following checks are still blocked or deliberately not automated:

| Check | Requirement before execution | Current state |
| --- | --- | --- |
| Actual single/multi-file structure, chapters, ordering, ebook pairing | Ordinary account plus representative library visibility | Administrator-visible MP3/M4B samples and chapters inspected; no indexed ebooks, confirmed multi-file edition, or ordinary-user proof |
| Download rights and reverse-proxy ranges | Allowed test file and ordinary download permission; activity-log side effect accepted | Administrator download policy true; small partial responses succeed; ordinary-user permission enforcement and failure/resume recovery remain open |
| Live CustomPrefs round trips, retry, deletion, bounded sizes | Dedicated ordinary-user token and disposable-write authorization | No authenticated write made |
| Same-user client/item isolation | Dedicated account and two disposable scopes varying one dimension at a time | Source and local fixture only; not part of automated live write mode |
| Other-user read/write denial | Two explicitly dedicated test accounts or authorized synthetic target, with negative write requests deferred until isolation is established | Not tested; never target another real user's existing namespace |
| Live session/progress effects | Explicit disposable media and permission to change only that test user's play state | Source only; ordinary catalog access is not permission to modify progress |
| Server restart, upgrade, destructive concurrency | Disposable actual Jellyfin installation with isolated synthetic library | File reopening and deterministic model only; real server never restarted or stressed |

No separate service or plugin implementation exists in this wave.
There is no remote or pull request. The parent owns integration and ticket closure.

### Follow-up boundaries

| Ticket | Work boundary | What this wave supplies |
| --- | --- | --- |
| `ta-qobz` | Disposable matching Jellyfin/Enhanced environment, synthetic media, two ordinary accounts, restart controls | Version/source references and the specific production-safety blockers |
| `boo-p58t` | Existing-storage protocol decision and actual concurrency, retry, deletion, isolation, limit, retention, and restart proof | Catalog/download results and the assessed Enhanced decision gate; keep in progress |
| `td-4nvl` | HTML/Markdown acquisition and its user-approved boundary | No indexed Book items; inspected item-ID file routes, no named HTML/Markdown acquisition endpoint; no local-import or plugin decision |
| `boo-u3cg`, `boo-7o92` | Catalog/edition implementation and verified offline downloads | Usable query/file interfaces; account restrictions and representative-data gaps remain explicit |

The parent can separate the catalog/download prerequisite from the storage decision if it wants to unblock implementation.
This wave does not change those dependency edges or close the research ticket.

### Final verification

All build/test commands used the pinned Nix development shell, one test command at a time.
No Android build, emulator/device action, browser preview, coverage job, or mutation job ran.
Hardening remains the parent's work after acceptance.

| Command | Final result |
| --- | --- |
| `nix develop --command flutter test test tool/research/jellyfin --reporter expanded` | 30 tests pass: 23 HTTP/CLI safety tests, four synthetic whole-set model tests, three application tests |
| `nix develop --command dart analyze tool/research/jellyfin` | No issues found |
| `nix develop --command dart format --output=none --set-exit-if-changed tool/research/jellyfin` | Four files inspected; zero changed |
| `git diff --check` | No whitespace errors |

Meaningful red tests preceded login, token-header handling, bounded media inspection, ordinary-user administrative-route avoidance, separate catalog-type counts, and distinct-container sampling.
The first full suite also exposed `SocketException: Connection reset by peer` in the raw-socket deadline fixture's write sink.
The fixture now handles that expected sink exception while still requiring request failure and peer-observed disconnection at the total 20-second deadline.
The focused deadline test and both later full-suite runs pass. The request deadline was not extended or disabled.
An analyzer suggestion to use `isNotEmpty` was corrected before the final full-suite run.

## Primary source index

All source paths below are relative to `jellyfin/jellyfin` at
`83d0d0e7f76e23e2e085c8ff67d28b772d35967d`.
For any path, fetch
`https://raw.githubusercontent.com/jellyfin/jellyfin/83d0d0e7f76e23e2e085c8ff67d28b772d35967d/<path>`.
This immutable commit, not `master`, is the basis of source inference.

| Reference | Source path | Relevant operations |
| --- | --- | --- |
| S1 | `Jellyfin.Api/Controllers/DisplayPreferencesController.cs` | GET/POST scope, MD5 ID mapping, reserved keys, separate saves |
| S2 | `Jellyfin.Server.Implementations/Users/DisplayPreferencesManager.cs` | Exact scope filtering, creation race handling, transactional full-set replacement |
| S3 | `src/Jellyfin.Database/Jellyfin.Database.Implementations/ModelConfiguration/CustomItemDisplayPreferencesConfiguration.cs` | Unique user/item/client/key index |
| S4 | `src/Jellyfin.Database/Jellyfin.Database.Implementations/Entities/CustomItemDisplayPreferences.cs` | Client length declaration and string value |
| S5 | `Jellyfin.Api/Helpers/RequestHelpers.cs` | `GetUserId` and session ownership |
| S6 | `Jellyfin.Api/Controllers/UserViewsController.cs` | Visible user views |
| S7 | `Emby.Server.Implementations/Library/Resolvers/Audio/AudioResolver.cs` | Books-library audio resolution and incomplete multi-part stacking |
| S8 | `Emby.Server.Implementations/Library/Resolvers/Books/BookResolver.cs` | Ebook extensions and directory rule |
| S9 | `MediaBrowser.Providers/MediaInfo/AudioFileProber.cs` | Embedded chapters, disc/track metadata, audiobook people metadata |
| S10 | `MediaBrowser.Controller/Entities/AudioBook.cs` | Resume/played support, downloadable local files |
| S11 | `MediaBrowser.Controller/Entities/Book.cs` | Ebook capabilities and series fallback |
| S12 | `Jellyfin.Api/Controllers/LibraryController.cs` | `/File`, `/Download`, range-enabled physical files and download activity |
| S13 | `Jellyfin.Server/Extensions/ApiServiceCollectionExtensions.cs` | Download permission policy |
| S14 | `Jellyfin.Api/Controllers/PlaystateController.cs` | Supported reporting routes and authenticated session selection |
| S15 | `Emby.Server.Implementations/Session/SessionManager.cs` | Progress persistence and server-time activity handling |
| S16 | `Emby.Server.Implementations/Library/UserDataManager.cs` | Item-scoped user-data writes and resume thresholds |
| S17 | `MediaBrowser.Controller/Entities/Audio/Audio.cs` | Metadata-derived custom keys and audio sort name |
| S18 | `Jellyfin.Api/Controllers/DevicesController.cs` | Elevated device listing |
| S19 | `Jellyfin.Api/Controllers/SessionController.cs` | Current session listing, not historical writer discovery |
| S20 | `Jellyfin.Api/Auth/DefaultAuthorizationPolicy/DefaultAuthorizationHandler.cs` | Unrestricted API-key distinction |
| S21 | `MediaBrowser.Model/Dto/BaseItemDto.cs`, `MediaBrowser.Model/Dto/MediaSourceInfo.cs` | Optional source identifiers, durations, media versions, and metadata |

The inspected S1 file had SHA-256 `02e900299719e961253d9b20146c0b36fdbc4244cb9e7c2975a6de94ef8a2e23`.
The inspected S2 file had SHA-256 `58bfa2776ddb30b436129d2e9765326f2baf59ecb1bacfdf7bc77a848112b04e`.
Public target evidence came from `/System/Info/Public` and `/api-docs/openapi.json` at the user-supplied origin.
Release/ref evidence came from GitHub's `repos/jellyfin/jellyfin/releases/latest` and `git/ref/tags/v12.4` endpoints on the research date.

### Enhanced primary source index

All extension source paths are relative to `n00bcodr/Jellyfin-Enhanced` at
`9bbf16c0de6662baeaa23e51c71505c15c560381`, not a moving branch.
Fetch source with `https://raw.githubusercontent.com/n00bcodr/Jellyfin-Enhanced/9bbf16c0de6662baeaa23e51c71505c15c560381/<path>`.

| Reference | Source path | Evidence |
| --- | --- | --- |
| E1 | `Jellyfin.Plugin.JellyfinEnhanced/Controllers/JellyfinEnhancedController.cs` | Version, authorization, bookmark/settings GET/POST, incremental add/delete, settings defaults |
| E2 | `Jellyfin.Plugin.JellyfinEnhanced/Configuration/UserConfigurationManager.cs` | Per-user files, process locks, strict reads, temporary-file replacement, read-side directory creation |
| E3 | `Jellyfin.Plugin.JellyfinEnhanced/Configuration/UserConfiguration.cs` | Typed settings, bookmark fields and dictionary |
| E4 | `Jellyfin.Plugin.JellyfinEnhanced/Helpers/UserHelper.cs` | Current-user claim lookup and administrator exception |
| E5 | `Jellyfin.Plugin.JellyfinEnhanced/js/enhanced/bookmarks/bookmarks.js` | Byte-matched deployed bookmark mutations, source-item meaning of syncedFrom, delete-all and orphan cleanup |
| E6 | `Jellyfin.Plugin.JellyfinEnhanced/js/enhanced/config.js` | Byte-matched complete-document HTTP save and session-local ordering/deduplication |
| E7 | `Jellyfin.Plugin.JellyfinEnhanced/JellyfinEnhanced.csproj`, `manifest.json` | Build targets and source version discrepancy |

`extension-evidence.json` records the measured frontend hashes, selected source hashes, and release provenance limits.
Public release/ref metadata came from `repos/n00bcodr/Jellyfin-Enhanced/releases/tags/12.14.0.0`
and `git/ref/tags/12.14.0.0` on GitHub's API.
