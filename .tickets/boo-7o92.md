---
id: boo-7o92
status: open
deps: [boo-u3cg]
links: []
created: 2026-11-01T21:37:34Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Implement verified downloads and media network policy

One policy governs streaming, audio downloads, ebook downloads, and reader assets. Prefer local files, block automatic transfers off Wi-Fi, and handle network handover.

## Design

docs/plans/bookfin.md

## Acceptance Criteria

Red-green tests cover Wi-Fi loss, unknown network, partial files, missing files, interruption, retry, cancellation, free space, and separate audio/ebook status. Test on Android.

