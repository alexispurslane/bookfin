---
id: boo-b7zj
status: open
deps: []
links: []
created: 2026-11-12T23:41:01Z
type: task
priority: 3
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Let the title-row action of a glass sheet return the result of the content

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: confirmed. `GlassSheetAction.onPressed` (lib/catalog/glass.dart:217-222) is a VoidCallback defined outside the content of the sheet, and the sheet pops with no result. The file order sheet (lib/catalog/book_page.dart:1271-1275) and the appearance sheet (lib/main.dart:686-689) therefore put their action button below the content, which UI rule 4 forbids. Give the builder a result slot that the content sets and the title-row action pops, then move both buttons into the title row.

