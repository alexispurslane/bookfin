---
id: td-yka3
status: open
deps: []
links: []
created: 2026-11-09T06:37:08Z
type: chore
priority: 4
assignee: Alexis Purslane
parent: boo-b2ey
---
# Describe layout's page breaks without the WebView reader as current

lib/reader/epub/layout.dart line 13 says that breaks follow CSS fragmentation as Chromium applies it to the WebView reader, as if that reader still exists. tc-rap6 removed the WebView reader and put the other lib/reader/epub comments into the past tense, but it did not edit layout.dart, because another agent worked on that file at the same time.

## Acceptance Criteria

The header comment of layout.dart names the former WebView reader in the past tense. No code changes.

