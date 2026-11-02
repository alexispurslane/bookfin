---
id: boo-gk92
status: open
deps: [boo-mx5i, boo-3oq0, boo-a4gi, t3-4isz, te-6x43, boo-2cgp, t7-bzzg, t3-ipk1, t6-t9po, t6-il6y]
links: []
created: 2026-11-01T21:37:34Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Harden accepted Android behavior and prepare release

After shared user acceptance, run coverage and mutation testing, close gaps, perform repeated lifecycle/network tests, and prepare Android packaging. Include a physical phone check for Bluetooth and battery restrictions.

## Design

docs/plans/bookfin.md

## Acceptance Criteria

Account for uncovered logic and surviving mutations. Verify the supported reader corpus, no automatic cellular transfer, durable history, cross-device sync, accessibility, and release installation.

