---
id: boo-61vt
status: open
deps: [boo-gxm8]
links: []
created: 2026-11-01T22:02:10Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
---
# Implement cream sepia typography motion and sunset appearance

Preserve the approved mockup structure nearly exactly. Implement cream and sepia day colors, warm dim night colors, Source Serif 4 reading text, Outfit headings, airy rounded controls, smooth transitions, and automatic local sunset/sunrise switching. Keep a manual override and an explicit system-theme fallback when no location is available.

## Design

docs/plans/bookfin.md

## Acceptance Criteria

Review day and night on Android and the shared T3 Device panel. Bundle fonts with licenses. Preserve feature layout and reading positions. Meet text/control contrast targets and respect reduced motion. Test sunset/sunrise, fallback, manual overrides, date/time-zone changes, and polar cases.

