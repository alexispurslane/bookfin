# Alternate original-source downloads

Ticket: `t9-04iu`. Baseline: `261d50eb48dbe78288d44419d692e27268430a78`.
Investigation date: November 2, 2026.
The downloader still refuses alternate sources. No new media endpoint or server component was added.

## Source evidence

The upstream source archive was fetched during this investigation through the project Nix shell.
Its SHA-256 matched `tool/research/sync/sources.json`:

- Repository: `https://github.com/jellyfin/jellyfin`.
- Commit: `83d0d0e7f76e23e2e085c8ff67d28b772d35967d`.
- Archive: `https://codeload.github.com/jellyfin/jellyfin/tar.gz/83d0d0e7f76e23e2e085c8ff67d28b772d35967d`.
- Archive SHA-256: `fa96b3e173525c871d3d0b2b3afd512bd692e2b2314935c223c1c44035ec7ea1`.

All upstream file references below use that commit, not the moving main branch.

| Upstream file and first line | Finding |
| --- | --- |
| `Jellyfin.Api/Controllers/LibraryController.cs:669` | Download accepts one route argument, `itemId`. It has no source selector. |
| `Jellyfin.Api/Controllers/LibraryController.cs:670` | Download requires the Download authorization policy. |
| `Jellyfin.Server/Extensions/ApiServiceCollectionExtensions.cs:72` | The Download policy requires `EnableContentDownloading`. |
| `Jellyfin.Api/Auth/UserPermissionPolicy/UserPermissionHandler.cs:29` | Ordinary users need that permission. API keys have a separate global-permission branch, which Bookfin does not use. |
| `Jellyfin.Api/Controllers/LibraryController.cs:680` | Download resolves the item for the authenticated user, then checks the item's `CanDownload(user)`. |
| `Emby.Server.Implementations/Library/LibraryManager.cs:1733` | User-bound lookup refuses items that are not visible to that user. |
| `MediaBrowser.Controller/Entities/BaseItem.cs:928` | Item download authorization requires the content-download permission. |
| `Jellyfin.Api/Controllers/LibraryController.cs:709` | The downloaded file comes from the resolved item's path, not a requested source path. |
| `MediaBrowser.Controller/Entities/BaseItem.cs:1180` | Channel sources can come from a provider. Their identifiers are not a general backing-item contract. |
| `MediaBrowser.Controller/Entities/BaseItem.cs:1205` | Core local sources sort the queried item's own source first. |
| `MediaBrowser.Controller/Entities/BaseItem.cs:1230` | A core local source receives the backing item's ID. |
| `MediaBrowser.Controller/Entities/Audio/Audio.cs:150` | Core Audio exposes only itself as a default source. |
| `MediaBrowser.Controller/Entities/AudioBook.cs:13` | AudioBook inherits that Audio source enumeration. |
| `MediaBrowser.Controller/Entities/Book.cs:14` | Book does not override the empty base source enumeration. Its unnamed original remains supported. |
| `Jellyfin.Api/Controllers/LibraryController.cs:109` | File has ordinary authentication, not the Download policy. It also serves the item path and has no source selector. |
| `Jellyfin.Api/Controllers/AudioController.cs:88` | Audio streaming is a playback endpoint, not the Download-authorized original-file endpoint. |
| `Jellyfin.Api/Helpers/StreamingHelpers.cs:131` | Playback has source selection. That does not make it a permitted download fallback. |

## Supported limits

An alternate source means a selected `SourceFile` whose media-source ID differs from its owning item ID.
The catalog owns that identity and its revision, which describes the selected file version.
The downloader must not change either value to make a request succeed.

| Candidate | Result |
| --- | --- |
| Download with `mediaSourceId` in the query | Not a selector. The action does not accept it and still serves the item original. |
| File with a source query | No source selection or Download-policy equivalence. Not used. |
| Static audio playback with a selected source | Playback authorization is not download authorization. Not used. |
| Download with an arbitrary media-source ID substituted as the item ID | Only meaningful if that ID independently identifies an authorized item and its original matches the selected source. No general binding is established for arbitrary catalog sources. Not used as an alternate-source resolver. |
| Download of a separately cataloged audio item | Already supported as that item's own original. This does not establish alternate-source support on another item. |

Core Audio and AudioBook do not expose multiple local sources on one item.
Book has no alternate-source enumeration either.
Video version grouping is outside Bookfin's book catalog and is not evidence for alternate audiobook or ebook sources.
Provider-supplied sources cannot be assumed to follow local backing-item identifiers.

The blocker is the missing supported binding between an arbitrary selected catalog source and a Download-authorized original.
Neither a query parameter nor list position supplies that binding.
No general alternate-source download route was established for the approved book types on the pinned server.
This is not a claim that every provider or future server version makes such a binding impossible.
Do not borrow the dedicated personal-record plugin to serve media.
Real-library acceptance remains with `boo-2cgp`; this investigation uses no production access.

## Disposable server observations

`alternate-source.json` records the successful ordinary-user run against a fresh core-only server on `127.0.0.1:7564`.
The server came from the existing pinned research flake, not another checkout's fixture.
Its reported version was `12.4.0`.
The runtime DLL SHA-256 matched the existing pin:
`c553ef86f47d4de0399be5cb13d3623b9df017bb5d655a4622c8e58334f0b39c`.
The binary and source archive were separately pinned; this investigation did not rebuild Jellyfin from source.

Two synthetic WAV files had different tones but equal lengths of 16,044 bytes.
Jellyfin cataloged both as AudioBook items, each with one source whose ID equaled its item ID.
The ordinary user had playback and download permission but no administrator permission.
An administrator created only this disposable fixture and changed its policies for refusal checks.
No plugin was installed or borrowed.

| Ordinary-user request | HTTP status | Observed bytes |
| --- | --- | --- |
| Download item A | 200 | Exactly file A, checked against its independently computed SHA-256. |
| Download item A with item B's source ID in `mediaSourceId` | 200 | Still exactly file A, not file B. Both files had equal byte counts. |
| Download item B as its own item | 200 | Exactly file B, checked against its independently computed SHA-256. |
| Download after disabling the account's download permission | 403 | No successful download and no File or playback request. |
| Download after restoring permission but hiding the library from the account | 404 | No successful download and no File or playback request. |

The probe made zero File or streaming requests.
Its HTTP client refused redirects and remote origins.
The owned server process exited, the private fixture was removed, and port 7564 stopped accepting connections.
Port 7565 was not used.
Passwords, tokens, server logs, and private runtime data were not published.

These observations characterize the actual Download action and its authorization, not an actual multi-source book item.
They do not establish a source-to-backing-item association for a provider's alternate source.
They also do not constitute live Bookfin, Android, private-library, reader-format, or interrupted-download acceptance.
EPUB, MOBI, and PDF remain the approved reader formats; this investigation adds no format support.

## Regression and implementation evidence

The old guard accepted a first-listed default source even when its ID differed from the item ID.
A synthetic HTTP server returned six original bytes with the selected source's expected length.
The downloader published those original bytes under the alternate source identity.
Length checks and local hashing did not detect that association error.

Before changing production code, the two first-listed alternate-source tests failed with:
`Expected: DownloadPhase.failed; Actual: DownloadPhase.downloaded`.
They covered an alternate listed alone and an alternate listed before the original.
A third regression showed the same failure for an explicitly listed empty source ID.
These were behavior failures, not missing-reference or syntax failures.

The source guard now requires the selected named source ID to equal its owning item ID.
The only unnamed-source exception is a Book whose fresh metadata has no media sources.
First position, default type, non-remote status, fresh download permission, and catalog-owned revision checks still apply.
The existing second source check runs after receipt, before publication.

The tests cover these observable outcomes:

- A first-listed alternate never receives the original, whether listed alone or beside the original.
- A listed empty source ID cannot claim the unnamed-Book exception.
- A selected second source never switches to the first source or another route.
- Ordinary-account and item-policy refusal prevent media requests.
- A missing source or a changed revision cannot reuse the old identity.
- Removal during receipt prevents publication.
- Download denial issues no File, playback, other-item, or other-source request.
- Supported item originals and metadata-free Book originals still download their exact synthetic bytes.

No catalog identity, revision format, stored download schema, or source-change recovery policy changed.
The production change adds no HTTP request and no new fallback.

## Final checks

All Dart commands ran through the existing pinned project Nix shell, one heavy command at a time.
Machine load and available memory were inspected before test runs and the disposable server run.
No app build was needed for the download guard and HTTP-test changes.

| Check | Result |
| --- | --- |
| `flutter test test/downloads/transfer_test.dart --plain-name 'a first-listed alternate source' --reporter expanded --concurrency=1`, before implementation | Two meaningful failures: originals were published as alternate sources. |
| `flutter test test/downloads/transfer_test.dart --plain-name 'a named media-source list' --reporter expanded --concurrency=1`, before implementation | One meaningful failure: a listed unnamed source was accepted. |
| `flutter test test/downloads/transfer_test.dart --reporter expanded --concurrency=1` | 46 tests passed, including eight added cases. |
| `flutter test --concurrency=1 --reporter expanded` | All 300 application tests passed. |
| `flutter analyze lib/downloads test/downloads` | No issues found. |
| `dart format --output=none --set-exit-if-changed lib/downloads/local_downloads.dart test/downloads/transfer_test.dart` | Two files checked, zero changes. |
| Disposable pinned core-server characterization | Passed byte-hash comparisons, ordinary-user 403 refusal, item-visibility 404 refusal, and private cleanup. |
| `git diff --check` | Passed. |

No device, browser, production-server, coverage, mutation, child-agent, or PR work ran.
The ticket remains in progress for orchestrator integration and disposition of the alternate-source blocker.
