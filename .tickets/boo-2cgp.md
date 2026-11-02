---
id: boo-2cgp
status: open
deps: [boo-u3cg, boo-7o92]
links: []
created: 2026-11-02T01:06:42Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
---
# Verify ordinary-user catalog and media integration

Validate catalog and downloads against disposable Jellyfin with two ordinary accounts, synthetic multi-file audiobooks and ebooks. Live admin research does not establish permission enforcement or pairing.

## Design

docs/plans/bookfin.md; authenticated research d327f68 pending permission-guard correction. Preserve remaining acceptance independently of catalog implementation.

## Acceptance Criteria

Prove account isolation, inaccessible items, disabled or missing download permission, multi-file ordering, distinct editions and ebook pairing. Verify progress writes only on synthetic media. Gate release acceptance; storage proof remains boo-p58t.

