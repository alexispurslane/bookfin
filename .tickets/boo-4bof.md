---
id: boo-4bof
status: open
deps: []
links: []
created: 2026-11-07T21:30:01Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
tags: [performance]
---
# Bring storage and CPU work in line with the engine rules

AGENTS.md engine rule 1 says the UI isolate does no synchronous storage access and no modest CPU work. Known breaks on main at e30abc7: Downloads.retainedStorage() calls FileSystemEntity.typeSync on two directories (lib/downloads/local_downloads.dart); the OCR store hashes and JSON-encodes a whole hOCR page and calls renameSync on the UI isolate (lib/reader/ocr_storage_io.dart). Sweep lib/ for other synchronous calls, whole-store JSON work, hashing, and large sorts that remain on the UI isolate after the boo-2otb, boo-t936 and boo-xifx merges.

## Acceptance Criteria

No *Sync file call runs on the UI isolate outside tests and invariant checkers. Each remaining inline CPU step has a comment that says why the hop costs more than the work.

