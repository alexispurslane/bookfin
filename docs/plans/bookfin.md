# Bookfin product and delivery plan

Status: approved for implementation, 2026-11-01. Implementation uses only GPT 6.1 Sol subagents at High reasoning effort. No application implementation exists at the starting baseline.

## Decisions from the user

- Target Android. Use Flutter and hot reload.
- Use T3 Code's Device panel for shared Android emulator testing from desktop or phone.
- Keep a browser preview for fast layout reviews and browser demonstrations.
- Show only book libraries, with audiobooks and accompanying ebooks organized together.
- Prefer downloaded audio. Prevent automatic streaming away from Wi-Fi.
- Show download availability in the book list.
- Support series, chapters, bookmarks, and recoverable seek and pause history.
- Read EPUB, MOBI, HTML, Markdown, and PDF, including PDF text reflow.
- Sync standard progress and playback activity with Jellyfin.
- Investigate Jellyfin storage for additional Bookfin records. A small Jellyfin plugin is acceptable if needed.

## Visual direction accepted in principle

The user approved the mockup's feature structure, information layout, and revised cream-and-sepia visual treatment. Preserve that structure nearly exactly. Implement the following visual requirements.

| Element | Direction |
| --- | --- |
| Day palette | Warm cream surfaces, sepia text, and restrained copper accents |
| Night palette | Deep warm-brown surfaces with muted cream text and softened sepia accents |
| Reading and book titles | Source Serif 4, bundled with the application |
| Large headings | Outfit, a geometric typeface with strong headline weights |
| Controls and spacing | Rounded surfaces, pill controls, generous space, and quiet separators |
| Motion | Smooth screen, filter, chapter-panel, playback-control, and theme transitions |

The HTML mockup embeds both fonts, so its appearance does not depend on a network font request. Font files and their SIL Open Font Licenses are in docs/mockups/fonts. These Latin subsets cover the demonstration text. The application needs suitable character coverage and font fallback for the user's library.

The mockup uses approximately 200 milliseconds for press feedback, 360–420 milliseconds for screen changes, and 600 milliseconds for palette changes. These are starting points for device review, not fixed accessibility requirements. Respect the platform's reduced-motion preference. Keep text readable throughout transitions. Maintain at least 4.5:1 contrast for normal text and 3:1 for large text and essential controls.

Enable automatic night appearance by default. Switch at local sunset and return at local sunrise. The night palette preserves the daytime hues while reducing surface and text brightness. It is an explicit palette, not a mathematical inversion of images or the whole screen.

Actual sunset times require a location. Support a selected city or optional approximate device location, with calculation on the device. If no location is available, follow Android's system night appearance and identify this fallback. Do not present an arbitrary evening hour as calculated sunset. Keep manual day and night overrides available. Recalculate after location, date, or time-zone changes, and define behavior for polar day and night.

The mockup's Daylight and After sunset controls preview the two palettes. They do not implement an Android sunset scheduler. Production behavior remains an implementation task.

## Book and edition model

A book is a work that the user recognizes by its title and author. An edition is a particular recording or text of that book. A file is one downloadable part of an edition.

A book can have several audio editions and several ebook editions. An audio edition can contain one M4B file or many ordered audio files. Chapters identify named ranges within that audio edition. File boundaries and chapter boundaries are separate facts.

A series is an ordered collection of books. Preserve explicit ordering, including fractional entries and side stories. Do not assume that Jellyfin's television-oriented series fields describe books correctly.

Each edition has its own resume position. Audio positions identify a file and a time within that file, measured in milliseconds of recorded audio. The player derives whole-edition time from the ordered files. Playback speed does not change the stored audio position.

Ebook positions identify a location in a particular edition. Use a stable text anchor where the format permits one. PDF positions also retain the source page. Do not equate an audio percentage with an ebook percentage. Automatic audio-to-text alignment is outside the initial scope.

Bookfin owns explicit book grouping, corrections, and series ordering when Jellyfin lacks them. Prefer trustworthy identifiers and explicit relationships. Offer possible matches for confirmation instead of silently merging books by similar titles. Keep links to the original Jellyfin items and media sources.

All persistent records belong to one Jellyfin server and user. Changing accounts must not expose another user's books or records. File replacement and changed editions must not silently reuse incompatible positions.

## Ownership and changes

| Owner | Stored information or decision | What causes it to change |
| --- | --- | --- |
| Jellyfin | Source files, library descriptions, standard per-item user progress | Jellyfin scans, metadata edits, Bookfin playback reports, other Jellyfin clients |
| Book catalog | Cached book descriptions, edition relationships, series order, source identifiers | Library refresh and explicit user corrections |
| Download manager | Transfer state and verified local files | Download requests, network changes, completion, removal, storage failures |
| Playback and reading session | Active edition and position | Play, pause, seek, chapter choice, bookmark restore, page movement |
| Personal record store | Durable resume positions, bookmarks, listening history, pending sync changes | Accepted session changes and merged remote records |
| Sync coordinator | Transfer status and conflict decisions | Connection availability and pending local or remote changes |

Keep one owner for each decision. The download manager decides whether a complete local source exists. The media access policy decides whether any remote media request is allowed. Both the player and the download manager obey that policy.

The session records the previous and resulting positions before a user-requested jump completes. All jump sources use this path, including the slider, chapter selection, notification controls, headset controls, bookmark restore, and history restore.

## Listening and downloads

The initial policy is local-file preference on every network, with no automatic media transfer on cellular, no connection, or unknown network type. Wi-Fi permits streaming when no complete local source exists. A separate explicit action can allow cellular transfer for the current session. Small metadata and progress requests are a separate policy from media transfer.

When Wi-Fi disappears during a stream, cancel further remote media requests. Continue from a verified local source when available. Otherwise pause with a clear explanation. Already buffered audio is not evidence that a book is downloaded.

Use the same transfer decision for audio, ebook files, and automatic downloads. Reader content must not fetch embedded remote resources outside the policy.

| Availability label | Exact meaning |
| --- | --- |
| Downloaded | All required files of the selected edition are locally complete and verified |
| Partial | Some required files are complete; the edition is not fully available offline |
| Downloading | A transfer is active, with bytes and progress visible |
| Waiting for Wi-Fi | A queued transfer cannot start under the current policy |
| Not downloaded | No complete local copy is available for the selected edition |
| Download failed | Transfer needs retry or user action; explain the cause |

Show audio and ebook availability separately. A downloaded EPUB must not imply that its audiobook is downloaded. The Downloaded filter shows fully downloaded audio editions for listening. Other books remain discoverable in the full library.

Support interrupted transfers, safe retry, cancellation, free-space checks, removal, and recovery after process death. Resume HTTP downloads only if server support and file identity make it safe. Publish a file as complete only after verification and an atomic final move. Do not silently evict completed downloads.

## Player and personal records

- Keep a persistent mini-player and a full player with large controls.
- Support chapter navigation, playback speed, configurable short jumps, sleep timer, and lock-screen controls.
- Save meaningful pause, resume, seek, chapter, interruption, and restore events. Do not create a visible history entry for every playback update.
- Group slider movement into one completed seek. Retain both the starting and resulting positions.
- Offer immediate Undo after a seek and a persistent history screen after that message disappears.
- A restore creates a new recorded action. It does not erase the actions that it reverses.
- Store bookmarks with an edition position, optional title, optional note, and stable identifier.
- Persist resume positions periodically and at lifecycle transitions. Test crash recovery separately from ordinary pause handling.
- Keep history across restarts. Decide retention and pruning rules before claiming that full history sync is complete.

## Reader scope and proof work

| Format | Intended experience | Required proof before package selection |
| --- | --- | --- |
| EPUB | Reflowing text, contents, font size, theme, search, saved position, bookmarks | Complex chapters, images, embedded fonts, large books, stable positions |
| HTML | Readable local document with images and internal links | Disable active content; resolve local assets without escaping the book |
| Markdown | Render headings, links, lists, code, and images | Stable positions and safe rendering of embedded HTML |
| MOBI | Read unencrypted supported MOBI variants through local parsing or conversion | Sample files, conversion quality, licensing, Android packaging, offline operation |
| PDF | Original pages and an optional reflowed text view | Text order, columns, headings, images, page-to-text anchors, license and binary size |

PDF reflow means extracting the document text and laying it out to the screen width. It is not zooming a page image. Tagged or simple text PDFs are the first target. Multi-column pages and tables can lose their reading order. Scanned pages need optical character recognition, which converts page images into text. Treat that as a separate feasibility item, with the original-page view always available.

Do not promise support for encrypted ebook content or every MOBI variant. Establish the supported corpus before selecting reader packages. A renderer or conversion library must work offline on Android and have an acceptable redistribution license. The Flutter UI can use native libraries when necessary.

## Sync designs considered

| Design | Extra installation | Extra-record storage | Tradeoff |
| --- | --- | --- | --- |
| A: Jellyfin only | None | Namespaced custom display preferences | Minimal setup, but concurrent writes and record discovery need proof |
| B: Jellyfin plus Bookfin plugin | One Jellyfin plugin | Plugin-owned per-user records | Explicit sync semantics, but more server maintenance |

Example A: create a bookmark offline, then upload it through Jellyfin display preferences. Example B: create the same bookmark, then upload it through the plugin's record API.

Both designs preserve local operation, standard Jellyfin progress reporting, and the same Flutter UI. The user chose A: prove Jellyfin-only storage before promising full sync. The user accepts a small plugin if the existing API is unsuitable. No separate sync service is planned.

### Findings and validation gate

Jellyfin 10.11.0's DisplayPreferencesController reads and writes custom string preferences scoped by user, item, and client. Its DisplayPreferencesManager deletes the previous custom preference set before inserting the supplied set. The inspected path exposes no conditional-write check. A simple shared JSON document can lose changes from concurrent writers.

This is a candidate transport, not a proven personal-data sync service. Test against the user's actual Jellyfin version and a disposable namespace. Prove round trips, ordinary-user permissions, separation between users, record discovery, size limits, concurrent writes, deletion, server restart, and upgrade behavior. Preserve unrelated settings. Do not place private user records in shared library metadata.

Per-device records can reduce concurrent writes, but discovering all devices and retaining deletions must also work. A read-merge-write loop alone does not eliminate races. Prefer the plugin if safe discovery and conflict handling need fragile workarounds.

The plugin path uses stable record identifiers, retry-safe writes, version checks, a list of changes since the previous sync, and explicit deletion records. These are requirements, not a settled endpoint or database design. Design that boundary when the feasibility ticket closes.

### Standard Jellyfin behavior

Use Jellyfin's supported playback start, progress, and stop reporting for normal activity. Map Bookfin's edition position to the correct Jellyfin file item and media source. Test both single-file and multi-file audiobooks. Do not invent a parent-level progress field when Jellyfin exposes progress only per item.

Keep pending offline progress locally. Reconcile it with newer server activity before uploading. Do not choose the greatest timestamp within the book as the winner: intentional rewinds and rereads are valid. Save both positions before resolving a genuine conflict. Do not replay every old progress tick as live listening activity after reconnecting.

Exact historical listening activity is a Bookfin record. Standard Jellyfin reporting does not establish that arbitrary historical activity can be backfilled with its original time.

## Tools and shared testing

Use self-contained HTML mockups with T3 Code's html_preview and html_render MCP tools. This toolchain is already available and displays interactive mockups in the conversation. Store source in docs/mockups. No external mockup service is required for this first design pass.

Use T3 Code's integrated browser for Flutter web demonstrations. Its browser was successfully opened during planning. Flutter documentation confirms that web hot reload is supported. The exact pinned Flutter version, web-server mode, and T3 connection must still pass a state-preserving reload test together.

Use T3 Code's Device panel as the primary Android test surface. On 2026-11-01, device_list found the device hub and agent tools installed, but no devices. Android was unavailable because command-line tools were missing at /Users/alexispurslane/Library/Android/sdk.

The setup task must provide Flutter, Dart, Java, Android build tools, and an ARM64 emulator image through the project Nix flake. Set required SDK variables in the dev shell. Resolve how T3's independently running device host discovers that SDK without putting toolchain variables in the user's shell profile or overwriting an existing SDK.

Register T3 project scripts only after their commands exist and run successfully. Preserve other scripts. Open the chosen emulator with device_list and device_open. Use the returned agent-device command for app launch, input, settings, and screen interaction. Build and test commands run through nix develop.

Phone access is not yet verified. Confirm that the user can view and control the same Device panel from the phone. Also verify browser access through the user's T3 connection. Do not assume that a desktop localhost URL is reachable on a phone. Avoid an unauthenticated public development server.

Browser demonstrations do not prove Android background playback, Wi-Fi policy, storage durability, or audio focus. Emulator tests also need a physical Android check for Bluetooth routing, OEM battery restrictions, and real network handovers before release.

## Delivery order and acceptance

1. Set up Nix, Flutter, Android, T3 scripts, and shared device access. Demonstrate a state-preserving hot reload and user interaction from the phone.
2. Prove Jellyfin integration with representative libraries and ordinary user permissions. Investigate metadata storage, item grouping, chapters, downloads, and progress. In parallel, test reader format candidates.
3. Build the first complete listening path: sign in, select book libraries, browse, download one whole book, disconnect, play, pause, and resume after app restart.
4. Add all media policy transitions, resilient transfers, background playback, chapter navigation, bookmarks, and seek history with Undo.
5. Add series organization, edition pairing, and the reader. Deliver EPUB, HTML, and Markdown first while MOBI and PDF proof work determines their implementation.
6. Implement extra-record sync using the validated Jellyfin transport or the plugin. Test two offline devices, conflicting resume positions, duplicate retries, and deleted bookmarks.
7. Harden and release Android builds after shared user testing.

Use red-green tests for behavior changes. Begin with user-visible behavior tests and make sure they fail for the intended reason. After implementation and user acceptance, measure coverage, run mutation testing, and account for surviving mutations. Record practical tool limits rather than claiming unsupported coverage.

The core test cases include Wi-Fi loss during streaming, a missing local file, a partial multi-file download, process death, an accidental chapter jump, restoring an old position, two devices editing offline, clock differences, and an ebook that is downloaded while its audio is not.

Use fake catalog and media fixtures for repeatable UI tests. Use actual Jellyfin and local playable files for integration tests. Keep credentials out of fixtures and request them through T3's secret input when needed.

## Remaining user inputs

- Jellyfin version and representative library organization, collected during integration setup.
- Representative unencrypted MOBI and PDF books to define the reader's compatibility target.
- Shared user testing as working Android features become available. The mockup's structure and revised visual treatment are approved.

## Sources checked

- Jellyfin 10.11.0 display preference controller: https://github.com/jellyfin/jellyfin/blob/v10.11.0/Jellyfin.Api/Controllers/DisplayPreferencesController.cs
- Jellyfin 10.11.0 display preference persistence: https://github.com/jellyfin/jellyfin/blob/v10.11.0/Jellyfin.Server.Implementations/Users/DisplayPreferencesManager.cs
- Jellyfin playback reporting controller, development branch: https://github.com/jellyfin/jellyfin/blob/master/Jellyfin.Api/Controllers/PlaystateController.cs
- Jellyfin 10.11.0 item model: https://github.com/jellyfin/jellyfin/blob/v10.11.0/MediaBrowser.Model/Dto/BaseItemDto.cs
- Flutter web development: https://docs.flutter.dev/platform-integration/web/building
- Flutter hot reload: https://docs.flutter.dev/tools/hot-reload

## Ticket index

Epic: boo-fs0n. All tickets reference this plan. No implementation tickets are started.

| Ticket | Work | Depends on |
| --- | --- | --- |
| boo-gxm8 | Set up Nix Flutter Android and shared T3 testing | None |
| boo-p58t | Prove Jellyfin catalog media and extra-record storage | boo-gxm8 |
| boo-73yj | Prove Android MOBI and PDF reflow support | boo-gxm8 |
| boo-u3cg | Build book catalog series and edition relationships | boo-p58t, boo-61vt |
| boo-7o92 | Implement verified downloads and media network policy | boo-u3cg |
| boo-sthf | Deliver offline playback chapters and Jellyfin progress | boo-7o92 |
| boo-6h8w | Add persistent seek recovery bookmarks and listening history | boo-sthf |
| boo-9wgg | Build EPUB HTML and Markdown reading | boo-u3cg, boo-7o92, boo-73yj |
| boo-mx5i | Add supported MOBI and PDF reflow reading | boo-9wgg |
| boo-3oq0 | Sync Bookfin records through validated Jellyfin storage | boo-p58t, boo-6h8w, boo-9wgg |
| boo-gk92 | Harden accepted Android behavior and prepare release | boo-mx5i, boo-3oq0 |
| boo-61vt | Implement cream/sepia appearance, fonts, motion, and sunset theme | boo-gxm8 |
