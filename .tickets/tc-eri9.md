---
id: tc-eri9
status: open
deps: []
links: []
created: 2026-11-10T22:18:31Z
type: bug
priority: 3
assignee: Alexis Purslane
---
# Make the personal-record invariant check work without SQLite

Found while verifying boo-lj72. LocalResumeStore.checkInvariants throws A kept view must match its cached account after a fresh preferences-only store reads an account. _read caches the opposite domain in _views, while preferences-only _readAccount restores without adding an _accounts entry. The checker assumes an _accounts entry for each kept view. PDF choices and reading records round-trip correctly through preferences; the same checker passes for SQLite. Reproduce with LocalResumeStore without openDatabase, save reading records, create a fresh store, read, then checkInvariants. Keep this repair separate from per-book PDF preferences.

## Acceptance Criteria

A fresh preferences-only LocalResumeStore can read records and pass checkInvariants without weakening SQLite invariant checks.

