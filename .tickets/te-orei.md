---
id: te-orei
status: open
deps: []
links: []
created: 2026-11-08T20:49:47Z
type: feature
priority: 3
assignee: Alexis Purslane
parent: boo-b2ey
---
# Read border-collapse and border-spacing for tables

Found in tc-txyr. Table layout uses Chromium's default border-spacing of 2 pixels for every table and draws each cell's own borders (separate borders). A book that sets border-collapse: collapse or another border-spacing draws double rules and other gaps than Chromium. Parse both properties in css.dart and use them in table.dart and LayoutRun._table.

