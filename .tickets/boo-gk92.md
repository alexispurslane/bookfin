---
id: boo-gk92
status: open
deps: [boo-mx5i, boo-3oq0, boo-a4gi, t3-4isz, te-6x43, boo-2cgp, t7-bzzg, t3-ipk1, t6-t9po, t6-il6y, boo-hxmd, boo-4088, boo-xyrl, boo-39cu]
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


## Notes

**2026-11-10T20:32:59Z**

PDF word-image integration 1330132 is green (2560 passed, 21 skipped). User already accepted Nihil crop fix and Trim margins; word view acceptance remains pending. Parent-owned coverage/mutation and invariant hardening must include the combined PDF changes after word acceptance, with no competing hardening jobs.

**2026-11-10T23:05:15Z**

After final word-view and per-book preference integration ff336de, host suite passes2649 tests/21 skipped. Normal app from ab5b9a3 is installed on Pixel. Include persistence and worker-save ordering in later accepted-behavior coverage/mutation work. No competing hardening jobs started; emulator performance remains blocked by boo-kdc6.
