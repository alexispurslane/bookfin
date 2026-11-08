---
id: t3-xi4e
status: closed
deps: []
links: []
created: 2026-11-08T00:15:11Z
type: task
priority: 4
assignee: Alexis Purslane
parent: boo-bquq
tags: [ui-rules]
---
# Make the player chapter list a leaf that the gallery can show

Rules: UI rule 2 (one component for each kind of thing).

Breaks:
- lib/playback/screen.dart, PlayerView._chapters: the chapter list is built inside the private sheet builder and calls playback.seekSource itself.
- lib/development/gallery.dart: the gallery shows no chapter list, because it cannot show this one. Before t9-rlgt it kept a private copy.

Target design:
A ChapterList leaf takes the chapters, the current chapter index and the position, and reports onChapter(chapter). PlayerView._chapters wires it to Playback and closes the sheet. The gallery shows the same leaf with sample chapters.

Owned files: lib/playback/screen.dart and its tests, then lib/development/gallery.dart.

## Acceptance Criteria

- The player chapter sheet and the gallery both show ChapterList.
- ChapterList calls no Playback method.

