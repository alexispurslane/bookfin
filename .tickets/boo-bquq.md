---
id: boo-bquq
status: open
deps: [boo-l5x3, boo-y6fb, t9-se8f, t9-4jqk, t9-112h, t9-dcld, boo-petv, boo-4bof, t9-sspn, t9-6u46, t9-xj41, t9-pols, boo-63ti, t9-kfdf, t9-d4kb, t9-8v91, boo-0km1, boo-7ua0, t9-3n2m, t9-cx1u, t9-rlgt, t6-2ghu, t6-epwo, t6-n8y3, t1-vtiy, t4-lvhh, ta-7oe6, tc-y4ij]
links: []
created: 2026-11-07T21:20:29Z
type: epic
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
tags: [ui-rules, engine-rules]
---
# Bring the app in line with the UI architecture and engine rules

This epic holds all conformance work for the two rule sets in AGENTS.md. The UI architecture rules are: data down and actions up, one component for each kind of thing, and depend on the minimum while the lowest widget subscribes. The engine rules are: keep the UI isolate free, start from the cache and refresh silently, and never lose listening history or a place in a book.

Target model: the data sources (catalog, Downloads, Playback, the reader session, appearance, record sync) and the tab or page controllers own every side effect and all long-lived data. Leaf widgets draw what they get and report events through callbacks, and each event gains meaning as it goes up. Each source exposes narrow listenables, such as the catalog's library, account and status, Downloads.watch(edition), and Playback's position, records and selection. The lowest widget that shows a value subscribes to it. The UI isolate does no synchronous storage access and no whole-store JSON work, hashing, grouping or sorting. At launch the app shows the cache and refreshes in the background with no spinner or label. Positions, history and bookmarks are written locally first and atomically, and are never lost.

Order of the work. Each child names its owned files. Two children that can run at once own no common file.
1. Wave 1: the data sources add narrow signals and move work off the UI isolate (t9-se8f catalog, t9-4jqk Downloads, boo-y6fb Playback, t9-112h reader session), the durability proof (boo-l5x3), and the app shell (t9-dcld). The shell adds stable tab entry widgets, so the tab tickets change only their own files. The source tickets keep their broad notifications, so every merge stays green.
2. Wave 2: the screens that depend only on wave 1 (t9-sspn library, t9-6u46 Downloads tab, t9-xj41 player, t9-pols settings and sync), plus boo-petv and boo-4bof.
3. Wave 3: the screens that build on wave 2 (t9-kfdf book page, t9-d4kb timeline, t9-8v91 reader screen), boo-63ti and boo-0km1.
4. Wave 4: boo-7ua0, t9-3n2m PDF viewport, t9-rlgt gallery, and t9-cx1u, which stops the broad notifications after every consumer moved.

Run `tk dep tree boo-bquq` for the full order.

## Notes

**2026-11-07T21:34:40Z**

From agent reports at 7fd0936: _BookfinAppState rebuilds the whole app on its 30-second clock and on every appearance change (boo-nxp8). PlayerView and PlaybackMiniPlayer subscribe to the whole Playback object, so the whole stage rebuilds at 5 Hz; the slider and time texts should subscribe to a narrow position signal (boo-jkf7). Check what boo-8dkw already changed before starting.

**2026-11-07T21:36:12Z**

boo-8dkw merged at its own merge commit after f47b367. The narrow position signal is now its own ticket, boo-y6fb; do it there, not here. The slider still calls beginSliderSeek and finishSliderSeek directly (rule 1).

**2026-11-07T21:47:00Z**

From boo-5jzo (merged 1fd38a5), rule breaks left in place: book page _Actions and _EditionPanel open playback and the reader, push routes, and confirm and run 'Separate source' themselves; Downloads _Summary asks about mobile data and changes the policy itself; _LeftoverInventory keeps a storage read in its own State; ListeningTimeline confirms and deletes inside its sheet; ReplacementStartNotice, RecordSaveStatus and the mini player buttons call Playback directly; the reader bookmarks panel edits a bookmark and restores a place itself; book, search and series pages rebuild on every services.changes. Shared pieces now exist to build on: confirmAction, EditionDownload.actions with onAction(DownloadAction), SectionLabel, BookfinPanel, SettingsGroup, ProgressLine, foundation/time.dart, showGlassSheet(title:), showGlassChoices, LibraryServices.page, StatusMessage.

**2026-11-07T21:55:32Z**

From boo-um68 (merged after c2b050f): the catalog has no narrow change signals, so LibraryShelf also rebuilds on busy notifications; the shell wraps SettingsPage and DownloadsPage in broad ListenableBuilders because those pages take values, not sources; DownloadsPage rebuilds on each download notice; the book page rebuilds all content below its top bar on each playback tick (services.activity merges Downloads and Playback); the shell calls the player and reader bind methods from _accessChanged (rule 1). New shared piece: ListenableSelector in lib/foundation/listenable_selector.dart.
