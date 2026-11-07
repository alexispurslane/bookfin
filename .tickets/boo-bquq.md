---
id: boo-bquq
status: open
deps: [boo-um68, boo-5jzo]
links: []
created: 2026-11-07T21:20:29Z
type: chore
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Bring existing widgets in line with the UI architecture rules

AGENTS.md now has UI architecture rules: data down, actions up; one component per kind of thing; minimal dependencies with low-level subscription. Known breaks: DownloadControls and row buttons call Downloads directly; the timeline calls Playback restore and delete; RecentListeningList calls playback.open; _LeftoverInventory owns a storage future in a leaf State. Audit and refactor after the current audit branches merge.


## Notes

**2026-11-07T21:34:40Z**

From agent reports at 7fd0936: _BookfinAppState rebuilds the whole app on its 30-second clock and on every appearance change (boo-nxp8). PlayerView and PlaybackMiniPlayer subscribe to the whole Playback object, so the whole stage rebuilds at 5 Hz; the slider and time texts should subscribe to a narrow position signal (boo-jkf7). Check what boo-8dkw already changed before starting.

**2026-11-07T21:36:12Z**

boo-8dkw merged at its own merge commit after f47b367. The narrow position signal is now its own ticket, boo-y6fb; do it there, not here. The slider still calls beginSliderSeek and finishSliderSeek directly (rule 1).

**2026-11-07T21:47:00Z**

From boo-5jzo (merged 1fd38a5), rule breaks left in place: book page _Actions and _EditionPanel open playback and the reader, push routes, and confirm and run 'Separate source' themselves; Downloads _Summary asks about mobile data and changes the policy itself; _LeftoverInventory keeps a storage read in its own State; ListeningTimeline confirms and deletes inside its sheet; ReplacementStartNotice, RecordSaveStatus and the mini player buttons call Playback directly; the reader bookmarks panel edits a bookmark and restores a place itself; book, search and series pages rebuild on every services.changes. Shared pieces now exist to build on: confirmAction, EditionDownload.actions with onAction(DownloadAction), SectionLabel, BookfinPanel, SettingsGroup, ProgressLine, foundation/time.dart, showGlassSheet(title:), showGlassChoices, LibraryServices.page, StatusMessage.
