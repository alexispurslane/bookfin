---
id: td-bz4y
status: open
deps: []
links: [te-c2tc]
created: 2026-11-13T21:58:52Z
type: chore
priority: 3
assignee: Alexis Purslane
parent: boo-b2ey
---
# Stabilize archive times in isolated EPUB research fixtures

Discovered by the te-c2tc repository-wide archive audit. The settled seven-builder cleanup covers root Flutter fixtures and tool/showcase_media.dart. Standalone research still has clock-dependent replacements in tool/research/readers/dart_compat/test/compat_test.dart (EPUB cover bytes test), Python synthetic EPUB creation in tool/research/epub_engines/test_prepare.py and test_calibrate.py, and tool/research/sync/fixture.py. Their current callers inspect payloads or server metadata, not rebuilt publication identities; no failing reader restore is claimed. Review and fix stable creation times in their own fixture owners without regenerating checked-in assets or running live server actions.

## Acceptance Criteria

Inventory each research creator; preserve payloads/order and fixture interfaces; prove controlled byte stability and changed-content sensitivity for genuine EPUB builders; run the corresponding isolated research checks. Do not change the SVG-only resource-serving security probes merely because they use ZIP.
