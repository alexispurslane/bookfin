---
id: boo-jlhy
status: in_progress
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



## Astra implementation launch

Original review base: 2ab1a6185456761e1c4d10ff06263c17711e28e3. Main baseline: 3,231 passing Flutter tests, 25 existing skips, clean affected analysis. Separate T3 worktree; implementation/direct fixes use codex/gpt-6-astra with reasoningEffort xhigh. One fresh read-only shared-worktree reviewer is authorized on the same model with reasoningEffort high; no other stage agents. Parent owns integration and closure. The brief includes atomic writes, failure-safe legacy migration (including inactive accounts), durable reopen evidence, and preservation of catalog freshness/corrections without the separate correction-store redesign.

Client request ID: bookfin-boo-jlhy-astra-20261113-1
Task ID: node:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-boo-jlhy-astra-20261113-1
Child thread ID: thread:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-boo-jlhy-astra-20261113-1
Thread: <t3-thread://v2/38d3e8fa-8572-4c2a-8a3b-2eb7c344dfce/thread:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-boo-jlhy-astra-20261113-1>
Launch status: running; stage not yet reported. Completion will be delivered automatically.
