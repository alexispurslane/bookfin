# Jellyfin feasibility evidence

Ticket: `boo-p58t`. Research date: November 1, 2026.
Base: `a6bfc1cc82b1ce8dc1705fee5408d868a9dfb6a1`.
Scope: supported Jellyfin APIs, safe probes, and a disposable local model.
No application code, plugin, server configuration, or library metadata changed.

An API is the server's application interface. OpenAPI is its machine-readable description.
A UUID is a generated unique identifier. A namespace reserves names for one client's records.
One KiB is 1,024 bytes. One MiB is 1,048,576 bytes.

## Result and recommendation

The user's server reports `12.4.0`, not the previously inspected 10.11.0.
Both its public information endpoint and its served API description report this version.
Public GET requests succeeded. Protected GET requests returned 401 without credentials.
The private credential request timed out. No authenticated request or write ran on that server.

Keep ordinary Jellyfin APIs for catalog access, original-file downloads, and playback reporting.
Do not promise complete personal-record sync through `CustomPrefs`.
`CustomPrefs` is Jellyfin's dictionary of custom display-preference strings.
The matching upstream source replaces that dictionary without a caller-supplied version check.
It exposes no public operation to list arbitrary preference scopes.
These omissions prevent a demonstrated solution for concurrent edits, device discovery, and durable deletions.

The evidence supports the already accepted small-plugin fallback for extra records.
This is a source-based recommendation, not a claim that the user's server lost real data.
Authenticated catalog and isolation checks remain blocked. Keep this ticket in progress.
Do not implement the plugin in this research ticket or silently reduce the promised sync behavior.

## Evidence classes

| Evidence class | What actually ran | What it establishes | What it does not establish |
| --- | --- | --- | --- |
| Live public HTTP | Public info, served OpenAPI, four protected GET requests without a token | Reported version, advertised route shapes, authentication barrier | Installed build commit, ordinary-user authorization, actual library organization |
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
The actual items for this user's library are unknown until authenticated inspection.
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
No such endpoint was called, and no other client's preferences were changed.
This research does not establish their implementation, installed plugin version, or suitability as a general Bookfin record store.
Do not infer that the server has no plugins, or reuse that client's files as Bookfin's disposable namespace.

## Local counterexamples and safety proof

The HTTP probe has fourteen passing behavior tests.
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
| A: existing `CustomPrefs` | None | Small ordinary-user settings in a private namespace are plausible; authenticated round trips still need proof | No demonstrated race-free writes, discoverable partitions, safe deletion retention, bounded growth, or change listing |
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
Recommend the accepted plugin fallback for the promised sync semantics.
The parent decides when to proceed with that fallback and settles its API design separately.

The separate HTML/Markdown acquisition gap has two user-visible choices:

| Design | Example use | Benefit | Cost |
| --- | --- | --- | --- |
| A: explicit local import | Select a Markdown file with Android's file picker | No extra server installation | That file does not come from Jellyfin discovery |
| B: plugin-backed library acquisition | Select an authorized HTML item exposed by a small plugin | Server-backed discovery and download | More server code, permission checks, and deployment maintenance |

Both keep offline reading, edition-specific positions, and active-content restrictions.
Neither is implemented or selected here. The parent must obtain the user's choice rather than silently inventing a source for these formats.

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

Request a dedicated ordinary-user session token through T3 private input with file delivery.
Do not request an administrator key. The request in this wave timed out after ninety seconds.
The implemented probe reads a token file; it does not currently perform username/password login.

```sh
nix develop --command dart run tool/research/jellyfin/probe.dart \
  https://jellyfin.example.com --secret-file /PRIVATE/T3/TOKEN_FILE
```

The default authenticated mode reads only the current user's policy and bounded catalog samples.
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
The probe's 16 KiB value, 32 KiB custom-set, 64 KiB request, and 4 MiB successful-response ceilings are client safety limits only.

The following checks are still blocked or deliberately not automated:

| Check | Requirement before execution | Current state |
| --- | --- | --- |
| Actual single/multi-file structure, chapters, ordering, ebook pairing | Ordinary account plus representative library visibility | No credentials; no private item inspected |
| Download rights and reverse-proxy ranges | Allowed test file and ordinary download permission; activity-log side effect accepted | No file requests made |
| Live CustomPrefs round trips, retry, deletion, bounded sizes | Dedicated ordinary-user token and disposable-write authorization | No authenticated write made |
| Same-user client/item isolation | Dedicated account and two disposable scopes varying one dimension at a time | Source and local fixture only; not part of automated live write mode |
| Other-user read/write denial | Two explicitly dedicated test accounts or authorized synthetic target, with negative write requests deferred until isolation is established | Not tested; never target another real user's existing namespace |
| Live session/progress effects | Explicit disposable media and permission to change only that test user's play state | Source only; ordinary catalog access is not permission to modify progress |
| Server restart, upgrade, destructive concurrency | Disposable actual Jellyfin installation with isolated synthetic library | File reopening and deterministic model only; real server never restarted or stressed |

No separate service or plugin implementation exists in this wave.
There is no remote or pull request. The parent owns integration and ticket closure.

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
