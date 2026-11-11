---
id: t9-dez7
status: open
deps: []
links: []
created: 2026-11-11T15:44:45Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-z3is
---
# Measure the text outline of an EPUB or MOBI edition in a worker isolate, cached by revision

Step 3 of design A in docs/plans/cross-edition-places.md. measureTextOutline gives the contents entries of an ebook edition (title, depth, start in visible characters from the book's start) and the visible characters of each part, counted as BookMap counts them. It parses every section once in one Isolate.run. A text place converts to and from visible characters. Measure the time for a large EPUB.

