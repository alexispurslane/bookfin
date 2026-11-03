---
id: t8-oitu
status: open
deps: []
links: []
created: 2026-11-03T20:34:28Z
type: bug
priority: 3
assignee: Alexis Purslane
parent: boo-fs0n
---
# Use format-neutral reader text when a PDF download is unavailable

Normal d8e1021 APK, emulator-5554: remove the downloaded PDF Acceptance single column; request redownload while Wi-Fi is not yet connected, then choose Read while the edition says Waiting for Wi-Fi. Reader correctly refuses unverified files, but also displays This EPUB is not open. Use the message above to retry. The source is an ordinary PDF. Evidence tool/evidence/reader/integrated/20261103/resumed/nonzero-active-read-after.txt. No implementation change in acceptance lane.

## Acceptance Criteria

A missing or waiting PDF original shows format-neutral wording or PDF wording. Preserve the existing verified-local-file guard and its retry action.
