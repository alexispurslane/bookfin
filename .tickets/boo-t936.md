---
id: boo-t936
status: open
deps: []
links: []
created: 2026-11-07T20:55:42Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Make Downloads.status a cached lookup

Audit P4: status() hashes every source file with SHA-256 and runs typeSync, lengthSync and listSync on the UI isolate, called from build for every tile and every edition. Store EditionDownload per edition, update it on events, compute source ids once at bind.

