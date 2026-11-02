# Catalog and account boundary

`lib/catalog/` implements Jellyfin sign-in, book-library selection, cached browsing, and local catalog corrections. Android is the production target. `lib/gallery.dart` remains a separate development entry point. No catalog action starts playback, reads an ebook, downloads media, or writes Jellyfin progress.

## Ownership

| Module | Responsibility |
| --- | --- |
| `jellyfin.dart` | Validate server addresses, authenticate, read book libraries, and fetch every selected catalog page. |
| `transport_io.dart` | Send Android and test HTTP requests without following redirects. |
| `transport_web.dart` | Send browser requests with redirects rejected and cookies omitted. |
| `model.dart` | Turn source metadata and explicit corrections into books, editions, and ordered files. |
| `store.dart` | Keep tokens in secure storage and catalog snapshots in separate, account-scoped storage. |
| `controller.dart` | Own the active account, cancel requests, publish complete saved catalogs, and serialize corrections. |
| `screen.dart` | Show real catalog state and collect confirmed corrections. |

The appearance controller still owns appearance. Catalog code does not store or change appearance preferences.

## Identities and positions

An `AccountScope` contains the normalized server URL, Jellyfin server ID, and Jellyfin user ID. Its `key` identifies one account on one server. A different server installation at the same URL has a different scope.

Each `SourceFile` retains the Jellyfin item ID and media-source ID. Its `key` identifies that source only within an `AccountScope`. Downstream storage must use both keys. Never use an item ID or source key alone as a global storage key.

`SourceFile.displayName` retains the source item's name, with its item ID as the fallback when no name exists. Details, recording choices, and file-order corrections use this name. They do not look up another account's cache to label a retained source.

`SourceFile.revision` describes the observed file version using modification metadata, size, container, and duration. An empty revision means that Jellyfin did not supply a usable version marker. It must not validate an existing position. A changed revision requires position reconciliation, not silent position reuse. This marker is metadata, not a cryptographic content checksum. The downloader still must verify bytes and replacement identity.

`Book.editions` contains separate audio and text editions. `Edition.files` is ordered. Multiple Jellyfin media sources for one item are alternate editions, not consecutive files. File boundaries and `SourceFile.chapters` are different facts. Chapter start times and audio duration are integer milliseconds of recorded audio, not wall-clock playback time. Derive a chapter end from the next chapter start or file duration.

`AudioPosition` stores an edition ID, source key, revision, and milliseconds within that source. `TextPosition` stores an edition ID, source key, revision, text anchor, and optional one-based source page. Each position has a `fits` guard. Neither position converts from the other. Personal-record persistence and sync remain separate tickets.

## Catalog operations

| Operation | Contract |
| --- | --- |
| `CatalogController.restore()` | Restore the secure session and its saved catalog without making a network request. Restored permission information is not fresh authorization. |
| `connect(server, username, password)` | Authenticate, save the token securely, restore only this account's cache, and list this account's book libraries. |
| `refresh(selected: ids)` | Validate the account, validate the selected book libraries, fetch all pages, and save one complete replacement snapshot. Omitting `selected` keeps the saved selection. |
| `cancel()` | Abort catalog network work and ignore late responses. Keep saved books and accepted correction saves. |
| `signOut()` | Immediately hide account data and delete the locally stored session. Keep the scoped catalog for a later authenticated return to that account. This is local sign-out, not remote token revocation. |
| `linkBooks(source, target)` | Confirm a shared book without combining recordings or equating audio and text positions. Keep the target book's details. |
| `combineAudio(book, editions)` | Confirm consecutive files of one recording. Reject text editions and alternate sources of the same item. |
| `separateEdition(sourceEdition)` | Move one original source edition to its own book and remove its recording relationship. |
| `correctBook(book, details)` | Persist a title, author, and optional series name and numeric order. Fractional and negative orders are retained. |
| `orderFiles(edition, sourceKeys)` | Persist an order containing every file exactly once. |
| `resetCorrections()` | Remove this account's local grouping, recording, order, and metadata corrections. |

No title comparison silently merges books. Matching titles and provider identifiers produce suggestions only. Explicit links work even when titles differ. Series membership and order come from explicit corrections, not Jellyfin television-series fields.

## Refresh and failure rules

`UserViews` supplies allowed libraries. Only views with `CollectionType` equal to `books` can be selected. Item requests always specify a selected parent and `AudioBook,Book,Audio` types. General `Audio` items enter only from these selected book libraries, never from a music or mixed library. The client does not search other libraries or fetch media to infer book relationships.

The requested optional fields use the Jellyfin v12.4 `ItemFields` contract, including `Etag`. `DateModified` is not requested as an `ItemFields` value. Returned modification metadata is retained when present, but the revision also supports the returned item tag. A strict local server fixture rejects unsupported field names.

Pages contain at most 200 items. Publication requires stable reported totals, unique item IDs, and the expected number of items. Empty early pages, duplicate items, changed totals, failed requests, and cancellation do not replace the saved catalog. Jellyfin does not provide an atomic catalog snapshot here. A concurrent same-count server edit can require another refresh.

Account replacement invalidates old responses. Network cancellation does not cancel an accepted local correction. Catalog and credential writes are serialized separately. A correction becomes visible only after its save succeeds. A catalog save failure leaves the previous saved catalog intact.

HTTP 401 hides cached account data and clears the local session. HTTP 403 and unavailable selected libraries hide the catalog until access is resolved. Network failures keep the last complete saved catalog available. No failure deletes the saved catalog as a fallback.

`CatalogController.checkInvariants()` is an on-demand diagnostic for tests or a debug command. It checks account ownership, selected-library membership, one owner for every source, and one source for a text edition. It does not recover from a failure. Internal publication has a debug-only account-ownership precondition.

## Credentials and downstream media access

Android uses `flutter_secure_storage` with encrypted preferences. Android backup is disabled in the manifest. Passwords are sent only in the sign-in JSON body and are cleared from the form on submission. Tokens are sent in headers, never URL parameters. Error text from Jellyfin is not shown or logged. Requests do not follow redirects. Only HTTPS is accepted, except loopback HTTP for local fixtures.

Catalog snapshots contain selected metadata, source identities, and corrections. They do not contain passwords, tokens, server filesystem paths, or remote media-source headers. Account scoping is access isolation within Bookfin, not encryption of catalog descriptions at rest.

The browser development build retains its session only in memory. It does not store tokens in browser local storage. Browser restart requires sign-in again, and cross-origin access requires Jellyfin CORS support. Android process restart supports secure-session restoration and offline browsing.

The downloader can consume the active account scope, `Book.editions`, and each ordered `SourceFile`. The player can consume that same edition and its chapter starts. Neither consumer may infer a downloaded state from a catalog entry. Currently every edition is truthfully not downloaded.

`JellyfinSession.canDownload` records Jellyfin's explicit `EnableContentDownloading` policy. Administrator status does not override it. A restored session or `verified == false` does not authorize remote media. The downloader must obtain fresh authorization, enforce the separate media-network policy, and check download permission before every media route, including `/Items/{id}/File`. This ticket exposes no file-download or streaming route, so it cannot provide a permission-bypassing fallback.

## Dependencies and remaining acceptance

`path_provider_foundation` is pinned to 2.4.4 because the secure-storage Windows dependency pulls the shared path-provider package into host tests. Version 2.6.0 adds a native Objective-C build hook that could not find this host's macOS SDK under the current Nix shell. The pin avoids changing global Xcode selection. Android secure storage still uses the Android secure-storage plugin. The Nix SDK includes platform 34 for that plugin, platform 35 for preferences, and platform 36 for the application. No SDK installer writes into the Nix store or another Android SDK.

Local HTTP fixtures establish application behavior, not deployed Jellyfin permissions. Android secure-storage restart, live sign-in, large-library layout, actual multi-file grouping, ebook pairing, and ordinary-user access still require coordinated acceptance. The supplied live research used an administrator and found no indexed ebooks. `boo-2cgp` retains deployment integration checks. `boo-p58t` retains full extra-record sync proof. No live credentials, target-server writes, device actions, or research-probe code are needed by the implementation tests.

The native-hook compatibility follow-up is `t7-fyql`. It depends on integration of `boo-u3cg`. WebAssembly is not claimed: the selected secure-storage package still has a legacy browser implementation. The release JavaScript build passes, and Bookfin's browser credential store remains memory-only.

## Implementation verification

Verified November 1, 2026, in America/New_York, from baseline `e2f2b4e`. The ticket remains in progress for parent integration. No emulator was opened or controlled. No authenticated target-server request was made, and ports 7357, 7358, and 7359 were untouched. No coverage or mutation job ran.

The final shell was recorded with `nix develop --profile .cache/dev-shell`. The commands below ran through that shell, using `nix develop .cache/dev-shell --command`. Android and web compilation ran sequentially.

| Check | Observed result |
| --- | --- |
| `flutter test --reporter expanded` | 94 tests passed, including the existing appearance and development-gallery tests. |
| `flutter analyze` | No issues found. The independent reader-research exclusion is unchanged. |
| `flutter build apk --debug` | Passed. Artifact: `build/app/outputs/flutter-apk/app-debug.apk`. |
| `flutter build web --release` | Passed. Artifact directory: `build/web`. |
| `git diff --check` | Passed before commit. |

Android compilation reported three Java 8 source/target obsolescence warnings from a dependency. The web build reported legacy secure-storage WebAssembly incompatibilities and the existing optional Cupertino font warning. Neither prevented the requested build. No Android runtime or browser-session acceptance is implied by compilation.

The red-green tests caught these concrete failures before their fixes:

| Behavior | Observed failing state | Protected result |
| --- | --- | --- |
| Basic catalog and relationships | No books or relationships were produced. | Single-file editions, confirmed multi-file order, alternate recordings, ebook links, and fractional series order are retained. |
| Pagination | Truncated, repeated, or changing pages could not satisfy completeness. | No partial snapshot replaces the last saved catalog. |
| Account cancellation | Late requests and a cancelled correction save were exercised separately. | Old responses stay hidden; accepted corrections survive network cancellation. |
| Account isolation | A signed-out correction dialog remained visible; an invalid account switch retained the old secure token. | Account changes dismiss old routes and remove the old session before a new sign-in attempt. |
| Permission changes | A new sign-in could expose a cached library whose access had been removed; an open correction remained visible after a forbidden response. | Removed or forbidden libraries and their open routes stay hidden without deleting saved records. |
| Cache failures | A cache read failure discarded successful sign-in. | Secure sign-in survives a cache failure and can load the catalog again. |
| File replacement and separation | Unversioned positions passed validation; separating a recording's first file lost the remaining explicit order. | Unknown revisions cannot validate positions; remaining file order is retained. |
| API contract | A strict fixture rejected an unsupported requested field and general audio was omitted. | Valid optional fields are requested, including the item tag; general audio is limited to selected book libraries. |
| Matching confirmation | Widget flows exercise cancellation before final confirmation. | Possible matches never silently merge books; the final confirmation saves the relationship. |
| Recording file choices | Choices displayed opaque source IDs instead of source names. | Named source files remain separate until the final recording confirmation; cancelling preserves separate editions. |

The synthetic fixtures are committed under `test/catalog/`. They contain invented accounts and metadata, not deployment credentials or private library records. These tests do not replace the ordinary-user, denied-download, real multi-file, and ebook-pairing checks tracked by `boo-2cgp`.
