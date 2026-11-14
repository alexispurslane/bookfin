---
id: t0-hwo8
status: open
deps: [boo-39cu]
links: []
created: 2026-11-14T00:11:03Z
type: bug
priority: 3
assignee: Alexis Purslane
parent: boo-fs0n
tags: [error-handling, follow-up]
---
# Propagate programming errors from leftover-file inventory

Recorded while resolving boo-39cu-F1: the pre-existing LocalDownloads._readLeftovers catches Object and presents programming Errors as ordinary inventory failures. Existing tests also use StateError for unavailable private storage, so fixing this requires distinguishing expected storage failures from contract bugs at that boundary. The review fix changes pending-status publication, not this existing handler. Static rule follow-up; no runtime reproduction claimed.

## Acceptance Criteria

Expected storage Exceptions keep the last inventory and disable stale removal actions. A programming Error reaches the caller or owning zone unchanged. Preserve account/source guards, corrupt-file retention and narrow leftover notifications. Add controlled failing tests before changing behavior.

## Notes

**2026-11-14T00:32:57Z**

Parent boo-39cu integration now classifies unavailable private storage as FileSystemException and stale removal guards as expected Exceptions, with actual confirmation-flow regressions. The broad Object recovery in _readLeftovers remains for this ticket to correct; preserve the new storage-failure and stale-confirmation coverage.
