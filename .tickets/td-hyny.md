---
id: td-hyny
status: open
deps: [t5-9tbu]
links: []
created: 2026-11-09T19:57:47Z
type: task
priority: 3
assignee: Alexis Purslane
parent: boo-b2ey
---
# Key a book's kept main text size by the cascade code, not by a hand-raised revision

Found in boo-1u66 on 2026-11-09. Admission now measures a book's main text size (Publication.mainTextSize) with the CSS cascade and keeps it in the admitted book. A change to the cascade that changes a book's main text size must raise Publication.revision by hand, or kept books keep a stale size: their main text then shows at the reader's size times the ratio of the new size to the stale one. Once the app reports its build to Dart (t5-9tbu), consider keying the kept measurement by the build, or measuring it in a test over the corpus that fails when the kept revision would give another size.

