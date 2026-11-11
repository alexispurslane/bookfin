---
id: boo-sy2d
status: in_progress
deps: [boo-yjq6]
links: []
created: 2026-11-11T20:09:32Z
type: feature
priority: 2
assignee: Alexis Purslane
parent: boo-tam0
---
# Open books faster: design A, admit at download and show the kept last page

Design A of docs/plans/faster-book-open.md, chosen by the user 2026-11-11.


## Notes

**2026-11-11T23:22:22Z**

User 2026-11-11: do the MOBI to EPUB conversion when the download completes. Design A's download-time admission must include the libmobi conversion and keep the converted EPUB, so a MOBI's first open takes the cached path like an EPUB (measured: conversion 253 ms of the MOBI's 508 ms first open after the quick wins).
