---
id: ta-ycs0
status: open
deps: []
links: []
created: 2026-11-10T01:44:22Z
type: bug
priority: 2
assignee: Alexis Purslane
parent: boo-m27l
---
# Give the reader's contents sheet a Contents heading

Found in the emulator check of t9-7fxw (docs/evidence/reader/dock-history/08-contents-no-tabs.png). Before t9-7fxw, the contents sheet had the tabs Contents and Bookmarks, and the Contents tab named the sheet. t9-7fxw removed the tabs, and _openContents in lib/reader/screen.dart calls _sheet without a title. The sheet now opens as a bare list of chapters with no heading, while the Search and Reading settings sheets have the glass title row. UI rule 4 says that a sheet's heading uses the glass sheet's own title row.

## Acceptance Criteria

The contents sheet opens with the glass title row Contents, the same as the Search and Reading settings sheets. A widget test finds the heading.

