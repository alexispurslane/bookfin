# Verified Android downloads

Real ordinary-account HTTP acceptance now runs production catalog and download
modules. Read `docs/acceptance/jellyfin-app.md` for results and remaining Android
release gates. The earlier implementation checks below remain historical.

Ticket: boo-7o92. Design: `docs/plans/bookfin.md`. Baseline: integrated `204fa5b`, with catalog `05bdc16`. This ticket stays in progress until parent integration.

## Ownership and boundaries

`Downloads` is the interface used by the catalog screens and the upcoming player. `LocalDownloads` owns transfer intent, file records, cancellation, and publication. It runs one HTTP transfer at a time. Public download, cancel, retry, and remove commands run in order. A retry cannot join the attempt that a cancellation is stopping.

The catalog remains the only owner of books, editions, and ordered source files. Downloads use the existing `AccountScope`, `Book`, `Edition`, and `SourceFile` objects. A saved file belongs to a source key and source revision, not a book title or mutable edition grouping. Catalog corrections therefore do not create a second catalog or copy media.

| Boundary | Responsibility |
| --- | --- |
| `MediaPolicy` | Select verified local media first; permit remote media only on known Wi-Fi or an explicitly allowed mobile session. |
| `LocalDownloads` | Own the account-bound queue, HTTP cancellation, source checks, file verification, and durable records. |
| Android method and event channels | Supply the application-private directory, available storage in bytes, and the validated default network type. |
| Catalog screens | Bind the current account and current catalog; display derived availability; request commands. |

The Android channels are small native boundaries in `MainActivity.kt`. They do not install another connectivity or filesystem package. The only added Dart package is `crypto` 3.0.7, pinned in `pubspec.yaml` and `pubspec.lock`. All build and test commands use the existing pinned Nix development shell.

## One media-network policy

`MediaPolicy.choose` returns local, remote, or blocked. Verified local media wins on every network. Remote media is blocked by default on mobile data, disconnected networks, unknown networks, unvalidated networks, and VPN connections whose underlying network is not known. Android classifies the active default network, rather than treating the presence of a Wi-Fi adapter as permission.

The Downloads screen offers a confirmation only when Android reports mobile data. The confirmation permits media for the current account session. Signing out, changing accounts or tokens, restarting the app, or selecting “Use Wi-Fi only” ends this permission. It never permits transfers on a disconnected or unknown network.

Network events close the active HTTP client as soon as permission is lost. A separate network generation invalidates callbacks even if Wi-Fi returns before the old request finishes. Queued requests retain their durable intent and resume on permitted Wi-Fi. A failed request does not repeatedly retry without a user action.

Metadata refresh remains under the catalog's separate policy. There is no player, streaming route, reader, or embedded-resource fetcher in this change. Future remote media consumers must use this same policy, observe its changes, cancel blocked requests, and obtain fresh server authorization before adding a route. A caller must not interpret a remote decision as authorization by Jellyfin.

## Fresh authorization and source identity

Before each media request the worker checks all of these conditions:

1. `/System/Info/Public` identifies the bound server.
2. `/Users/Me` identifies the bound user and explicitly returns `Policy.EnableContentDownloading == true`.
3. Fresh item details explicitly return `CanDownload == true`.
4. The selected source is the first default, non-remote source for that item. A Book without MediaSources uses its unnamed original source, matching the catalog model.
5. Rebuilding that item through the existing catalog model gives the same source key and nonempty revision.

Administrator status does not override a false or missing permission. A cached `JellyfinSession.canDownload` value never grants remote access. Tokens are headers, never URL parameters. Redirects are refused. Response error bodies and authentication headers are not displayed or logged.

The only media route is `/Items/{id}/Download`. Denial never triggers `/File`, a streaming route, or another source. Jellyfin's original-file Download route has no selected-media-source parameter. The downloader therefore fails closed for an alternate source instead of attaching the original file to the wrong edition. Further source-specific support is tracked by t9-04iu. The parent-owned live probe permission correction is not copied or changed here.

Source details are checked again after receipt and hashing, before final publication. Replacing the source during a transfer cannot publish bytes under the former source revision. Real-server ordinary-user and format acceptance remains in boo-2cgp.

## Storage and verification

Android stores files under `filesDir/bookfin-media`, not Android's cache directory or shared Downloads directory. Account directories use SHA-256 of the existing account key, which includes server address, server ID, and user ID. Source directories use SHA-256 of the existing source key and revision. Neither path contains a token or server filesystem path.

Each source directory contains only downloader-owned names:

| Name | Meaning |
| --- | --- |
| `partial` | An unfinished transfer; never returned as a complete local file. |
| `complete` | A verified file moved into place atomically. |
| `record.json` | The durable request, source revision, length, validator, digest, and sanitized failure. |
| `record.next` | A flushed replacement record, atomically renamed over `record.json`. |

The file is flushed, checked against the HTTP and catalog lengths, and hashed with SHA-256 before the final move. The record is flushed separately. A crash between the file move and record publication is conservative: the next launch does not claim that an unrecorded file is complete. A fully received but unpublished prefix can be downloaded again.

Jellyfin's source ETag is revision metadata, not a promised file checksum. The HTTP ETag is a resume validator. The saved SHA-256 digest detects later corruption of the local copy; it is not a server-provided cryptographic attestation. The implementation does not assume that Jellyfin provides such an attestation.

Resume requires a saved strong HTTP ETag, a known total length, an existing prefix shorter than that length, and a fresh matching source revision. The request sends `Range` and `If-Range`. A 206 response must match the exact requested start, final byte, total length, response length, and ETag. An invalid range or changed ETag discards the prefix and asks for a fresh retry. A 200 response replaces the prefix instead of appending it. Without a strong validator, the transfer restarts safely. Encoded or unknown-length responses fail closed.

Free storage is checked before the media request and during writes, keeping a 65,536-byte margin. Storage failures leave an incomplete file and a retryable explanation, never a downloaded edition. A record-write failure is also a download failure. If storage cannot save a cancellation, its error remains visible; durable cancellation cannot be promised until storage works again.

Removal first cancels the edition. It removes only the four owned filenames for its source revisions in the current account. Old revisions must have a matching saved source key and a matching derived directory name. Unrelated files and symbolic links are not followed or deleted. Completed old revisions are otherwise retained, not silently evicted. Files from deselected or removed catalog items stay private and disappear from active catalog availability. The Retained storage section provides explicit management under t9-k4lf.

Android backup stays disabled. Uninstalling the app removes its private media. No foreground service, OS download manager, or background scheduling guarantee is claimed. A queued transfer can recover when the app starts again; it does not run while its process is absent.

## Availability and user actions

An edition is Downloaded only when every current source file is complete and verified. Files are hashed on account restoration, foreground revalidation, and player lookup. Status rendering also checks presence and length. Missing files lose their complete status. A saved byte count from a missing complete file cannot become progress for a queued retry.

Audio and ebook availability appear separately in the book list. For multiple editions of one kind, the list shows the best available edition; it does not claim that every edition is downloaded. The Downloaded filter requires at least one fully downloaded audio edition. An ebook alone never satisfies the listening filter.

Book details expose download, retry, cancel, and confirmed removal. Downloads is an enabled bottom-navigation destination for a connected account. It shows bytes, required-file counts, whole-edition state, failures, and Wi-Fi/mobile permission. Cancelling retains verified files and a safe prefix. If only some required files are complete, the remaining edition is Partial after cancellation. During a failure, the file count still shows that partial progress.

The browser shares these screens but reports that local downloads are available in the Android app. It never simulates Android storage, downloaded files, playback, or reading.

## Retained storage

Downloads remains available when no library is selected. Its separate Retained storage section lists local source revisions outside the current catalog. This includes deselected libraries, removed Jellyfin items, and superseded source revisions. It does not label these files as downloaded editions or offer playback, retry, or new transfer permission.

`LocalDownloads` remains the only storage owner. An inventory request waits for account restoration, then reads the current account's existing private directory. No new durable index, account-discovery mechanism, or catalog copy exists. Each row reports the combined lengths, in bytes, of regular `complete` and `partial` files. Record files, unrelated filenames, empty directories, and linked files do not contribute to that number. Inventory does not hash media or claim that retained bytes are playable.

Saved records contain source identifiers, not book titles. Identified rows therefore show the saved source key and revision. Changing accounts immediately invalidates pending inventory reads and held removal confirmations. Changing the selected catalog also invalidates held confirmations. A late result from the previous account cannot populate the new account's view.

Removal requires confirmation for one retained source revision. The storage owner serializes removal with existing download commands, waits for restoration, and rechecks account, catalog membership, saved identity, and directory containment. It deletes only regular downloader-owned files in that source revision's directory. Other source revisions, current editions, other accounts, unknown files, and symbolic links remain untouched. Existing edition removal still removes that edition's identified old revisions through the same ownership and deletion checks.

An identified record must contain a nonempty source key and revision whose SHA-256 directory name matches the existing storage format. The record must be a regular file of at most 65,536 bytes. Missing, malformed, oversized, unreadable, or linked identity records cannot authorize retained removal. Recognizable storage directories with unidentifiable media remain visible as Unidentified stored files, without a removal action. The app does not infer ownership from a title, another account, or an arbitrary directory name. Unknown unrelated directories are not a cleanup target.

Catalog changes stop the affected transfer before restoration finishes. Unreachable files are never queued by inventory or automatically evicted. Reselecting a source restores the existing download rules, including verification before local playback and any previously saved transfer intent. Explicit retained removal clears its saved transfer intent with its owned files. A corrupt retained file cannot become playable merely because the library is reselected.

If private storage cannot be read, the section reports the failure and hides the previous rows. Refresh storage retries the inventory. Directory and file checks reject symbolic links and path traversal; they do not claim operating-system descriptor locking against a hostile process changing paths between filesystem calls.

Host verification and the separate Android runtime acceptance gap are recorded in `docs/acceptance/retained-downloads.md`.

## Player-facing interface

The existing `Downloads` interface declares:

```dart
  Future<Uri?> localFile(SourceFile source);
```

where

- `Downloads` is the transfer owner bound to the current catalog account.
- `localFile` checks that the source belongs to that account's current catalog and that its saved revision, file length, and SHA-256 digest match.
- `source` is an existing ordered `SourceFile` from the selected `Edition`.
- `SourceFile` is the catalog's source identity, revision, container, size, duration, and chapter description.
- `Future` means that verification finishes asynchronously.
- `Uri` is Dart's location type; a successful result is an application-private file location, not a remote URL.
- A null result means that no verified local file is available. It never returns a partial file or silently requests media.

The lookup waits for account restoration to finish before declaring a saved file unavailable. The player keeps the same `SourceFile` and edition ordering for positions. It must look up each required source, not turn one successful file into whole-edition completeness. A returned URI is a checked location, not a lock against later user removal. Handle a file that disappears before it is opened. `MediaPolicy` supplies the local-first decision for the upcoming remote path.

## Invariants

`LocalDownloads.checkInvariants()` is an on-demand diagnostic available in every build. It does not catch or recover from a failed invariant. The module requires these properties:

1. A signed-out owner exposes no account records or queued sources.
2. Each record identifies one current source key and revision.
3. A complete record has a digest, a positive verified length, and the same completed byte count.
4. Queued sources agree with durable requested flags and have no recorded failure.

The internal publication operation has a debug-only ownership and length precondition. Public edition arguments use ordinary always-on guards. Account and network generations invalidate asynchronous callbacks before publication.

## Red-green evidence

The first policy tests failed on local-first selection and explicit mobile permission. The initial transfer owner compiled but performed no work. All 14 initial transfer behaviors then failed with expected phase differences, not missing references. The core implementation made them pass.

Further tests found and reproduced these real errors before their fixes:

| Behavior | Observed meaningful failure | Correction |
| --- | --- | --- |
| Request during account switch | A waiting request reached an empty new-account record map. | Capture the account generation before waiting and check it after disk operations. |
| Fresh authenticated identity | A token for another user could pass a user-by-ID check. | Use `/Users/Me` and compare its ID to the bound account. |
| Existing authorization routes | A fixture permitting only catalog-compatible authorization routes rejected the download. | Use public server information and the current-user route. |
| Replacement during transfer | The old source revision was marked Downloaded. | Check fresh source details again before publication. |
| Failed manifest write | The write error escaped the command. | Publish a storage failure, stop that request, and preserve retryability. |
| Immediate cancel then retry | The old attempt turned the new request into Download failed. | Serialize public commands and wait for cancellation before retry. |
| Removing old revisions | The old complete file survived explicit removal. | Match saved revision ownership and remove only owned filenames. |
| Missing complete file | A queued retry still displayed six nonexistent bytes. | Read the actual prefix length before queueing the retry. |
| Lookup during startup | A player lookup returned null before saved-file verification finished. | Wait for account restoration and reject a changed account generation. |

The 34 focused tests also cover unknown/disconnected/mobile networks, Wi-Fi loss during bytes, explicit retry, multi-file partial completion, a separately downloaded ebook, interruption and restart, strong-validator range resume, invalid ranges, changed ETags, ignored ranges, free-space exhaustion before and during transfer, corrupt or missing files, authorization denial, sign-out, account/server isolation, queued restart, and the Downloads controls. No coverage or mutation run has started.

## Android observations

Observed November 1, 2026, in America/New_York, on the local Android emulator `emulator-5554`. Every app launch, input, and setting change used the session-bound T3 `agent-device` command. T3 `device_screenshot` and local device-command screenshots were used to inspect the screen. The setup build was signed out before testing. No production credentials or real Jellyfin server were used.

`tool/download_fixture.dart` is a disposable loopback HTTP fixture. Its bytes are explicitly synthetic and not playable books. It bound host port 61253, with an emulator-only reverse port forward. Ports 7357, 7358, 7359, and 7364 were untouched.

| Android exercise | Observed result |
| --- | --- |
| Real sign-in and catalog UI against the fixture | Connected a synthetic ordinary user, selected the synthetic book library, and listed separate audio/text states. |
| Text download | Stored six bytes privately and showed Downloaded with 1 / 1 files; audio remained not downloaded. |
| Wi-Fi disabled during a 6,291,456-byte audio transfer | Progress stopped at 393,216 bytes with 0 / 1 files and Waiting for Wi-Fi. |
| Mobile data remained available | Downloads showed Mobile data · Waiting for Wi-Fi and required an explicit session action. No mobile override was granted. |
| Wi-Fi and mobile data both disabled | Downloads showed Offline · Waiting for Wi-Fi; the byte count stayed 393,216. |
| App process relaunched while disconnected | The queued prefix and downloaded text survived secure account restoration. Neither became a fictitious complete audio file. |
| Wi-Fi restored | The fixture received a resumed request beginning at byte 393,216. The audio completed at 6,291,456 bytes. |
| Download returned 403, then allowed on explicit Retry | The second audio showed a sanitized denial, then completed at 1,048,576 bytes after Retry. |
| Grouped the two existing audio sources with the catalog's confirmed correction | Removing the smaller source produced Partial with 6,291,456 / 7,340,032 bytes and 1 / 2 files. Retry fetched only the missing source and produced Downloaded with 2 / 2 files. |
| Explicit Cancel during a new two-file download | The edition became Partial at 4,456,448 bytes with 1 / 2 files. Retry resumed the unfinished source at byte 3,407,872, preserving the completed source. |
| Process relaunched during that active retry | The next request resumed at byte 3,604,480. Both sources completed and their private-file hashes still matched. |
| Final APK installed and opened | The saved two-file audio and ebook were verified after account restoration, with no new media requests. |
| Linked the ebook to the same book, then removed only its audio | The book list showed Audio · Not downloaded and Ebook · Downloaded. The Downloaded listening filter showed no book. |
| Confirmed removal through Downloads | The two-file audio and the separate ebook were removed independently. Downloads became empty, and no downloader-owned files remained. |
| Final sign-out | The synthetic account disappeared, Downloads became disabled, and the app returned to its sign-in screen. |

Android's `sha256sum` on the actual private files matched an independent host calculation for all three synthetic files:

| File length in bytes | SHA-256 |
| --- | --- |
| 6 | `2efb1047074f7a387fa60c82d2b05bc742cfaf8163ccbb2012cb61108f87fa4f` |
| 1,048,576 | `a3f1b4f1e7ccf5ebb174809fdb35de6026d1ab93b1e33ba2b08e2e85a913bee1` |
| 6,291,456 | `5245991fce128f44015f90caea2bad151423fd312a30a4f04c2da0c83011cd8e` |

These checks prove emulator file storage, UI wiring, multi-file availability, network handover, and resume against the synthetic fixture. Multi-file failure, malicious ranges, corruption, disk-full conditions, and account races were exercised by host tests, not by filling the emulator disk or using production media. They do not establish physical-phone behavior, actual Jellyfin deployment acceptance, playable format compatibility, or background-transfer guarantees.

## Final checks

Final checks ran sequentially through `nix develop .cache/dev-shell --command`, with that shell profile created from the project's pinned flake. No heavy checks ran together.

| Command | Observed result |
| --- | --- |
| `dart format --output none --set-exit-if-changed lib/downloads lib/catalog/screen.dart lib/main.dart test/downloads tool/download_fixture.dart` | Passed; 12 files checked, zero changed. |
| `flutter test --reporter expanded` | 144 tests passed: the 110 integrated tests and 34 download tests. |
| `bash test/sdk_link_test.sh` | Passed all additive-link, repeatability, existing-tool refusal, and missing-SDK checks. |
| `flutter analyze` | No issues found. |
| `flutter build apk --debug` | Passed; final APK installed and exercised on the emulator. |
| `flutter build web --release` | Passed for JavaScript. The existing secure-storage WebAssembly limitation and a nonfatal Cupertino font warning remain; no WebAssembly support is claimed. |
| `git diff --check` | Passed. |

Wi-Fi and mobile data were restored to their initial enabled settings. The fixture was stopped, its reverse port forward was removed, and only this thread's device session was closed with `shutdown: false`. The emulator was left running and the app signed out. No secret file was read, no production request was sent, no preview server was changed, and no coverage or mutation command ran. No PR was created. The parent owns integration and ticket closure; no product decision is required for this implementation.


## Parent review corrections

The parent reproduced all four static review findings with five meaningful failing tests: replacement-response interruption retained three old bytes under the new validator; cancellation waited for unrelated media; immediate cancel and remove missed restored requests; and an early file denial hid the active state of later files.

Replacement responses now discard the prior prefix before saving the new validator. The regression restarts the download owner and checks the resulting replacement bytes. Cancellation saves disabled requests before waiting for only the affected active transfer to close. All serialized commands wait for account restoration and recheck account generation before execution. Queued work takes display precedence over a file error, preserving Cancel while keeping the error message.

Parent verification: 149 application tests pass, analysis has no issues, and the changed Dart files are formatted through the pinned Nix shell. The five new tests failed before implementation; the existing 144 tests remain green. Logs: /tmp/bookfin-download-fixes-red.log, /tmp/bookfin-download-fixes-suite.log, /tmp/bookfin-download-fixes-analyze.log. These corrections have not yet been inspected on Android; earlier Android observations describe the builder head. Independent correction review and integration remain pending. No coverage or mutation jobs ran.
