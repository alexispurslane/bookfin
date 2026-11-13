---
id: boo-jlhy
status: open
deps: []
links: []
created: 2026-11-12T23:41:00Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Keep the saved catalog in its own file, outside the shared preferences DataStore

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: confirmed code path. The DataStore rewrite behavior comes from its documentation and was not measured here. lib/catalog/store.dart:157-169 writes the whole saved catalog (3.9 MB for 1478 books, measured in boo-8v53) through `SharedPreferencesAsync`. On Android that API keeps every key of every caller in one DataStore file, and DataStore rewrites the whole file for each edit. lib/reader/reading_speed.dart:133 writes a short value on forward page turns, so each such turn rewrites the multi-megabyte file. The first preference read at launch parses the whole file before `runApp`. The catalogs of old accounts stay in the file. Give the catalog an atomic file store of its own (temporary file, then rename) with the IO off the UI isolate. Move the old key once, then delete it. Related: boo-8v53, t4-4d21.

