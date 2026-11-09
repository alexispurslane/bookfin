---
id: boo-2td2
status: open
deps: []
links: []
created: 2026-11-09T13:15:58Z
type: feature
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
---
# Show every reader sheet as glass, and give the note sheet a better Go to note

User request (2026-11-09): the footnote sheet must be a glass pop-up like the app's other bottom cards, and this must hold everywhere (AGENTS.md UI rule 4, added the same day). Today the reader shows its sheets (contents and bookmarks, search, appearance, notes) on the theme's plain sheet through showGlassSheet(glass: false), because the reader was meant to keep its own look. Remove that exception: every reader sheet is a glass pane (showGlassSheet with the open book, so the glass takes the book's cover like the other sheets), and delete the glass: false variant when nothing uses it (lib/development/gallery.dart uses it too). The user also finds the note sheet's Go to note button ugly and awkwardly placed (a tonal filled button alone at the bottom right, under the note text). Move the action into the glass sheet's title row: the heading 'Note' on the left and a quiet Go to note action on the right in the same row, as part of showGlassSheet's title (add an optional trailing action to the shared title row, so other sheets can use it too). Keep the page readable behind the sheet, keep the reader's paper colors inside the note text, and check both themes.

