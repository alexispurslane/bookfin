---
id: boo-xyrl
status: in_progress
deps: [boo-pwx7]
links: []
created: 2026-11-07T15:30:28Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
---
# Clear local data after uploading unsynced personal records


## Notes

**2026-11-13T21:43:34Z**

Parent asked the user on 2026-11-13 whether Clear data applies to the current account or every account previously used on this phone. Both designs preserve personal records, require confirmation, upload unsynced records before clearing downloaded files/covers/saved library, and stop on a required upload failure. All-account clearing may need credentials for prior accounts. This scope choice is pending; no implementation lead started. Existing approved behavior is docs/plans/bookfin.md, Library redesign, Clear data.

## User decision and implementation scope — 2026-11-13

The user selected the current account. Confirm the action through shared glass,
upload its unsynced personal records first, then clear only that account's
downloaded files, covers and saved library. Retain personal records and all other
accounts. A failed required save or upload stops removal. Bind the action to the
account that was confirmed; a later account change must never redirect it.

The user also selected deferred removal of a playing audiobook (boo-39cu): keep
playing, then remove after a saved pause or book switch. Reuse Downloads' removal
ownership for Clear data; do not bypass its active-read/playback protection with
a recursive deletion. Coordinate integration with boo-39cu, without inventing a
second pending-removal mechanism. Test real persistence and failure ordering.

Parent owns integration, device acceptance, hardening and closure. No device or
live account action is needed to implement and verify the host behavior.

## Launch accepted — 2026-11-13

Base: `2f5f0393d4d5961627b7eb84f7c2f7725ab762aa`.
Task ID: `node:delegated-task:command%3Amcp%3A42e1fbbe-e54d-4e0d-8253-f080c4fbe734%3Adelegate-task%3Abookfin-boo-xyrl-astra-20261113-1`.
Child thread ID: `thread:delegated-task:command%3Amcp%3A42e1fbbe-e54d-4e0d-8253-f080c4fbe734%3Adelegate-task%3Abookfin-boo-xyrl-astra-20261113-1`.
Thread: <t3-thread://v2/38d3e8fa-8572-4c2a-8a3b-2eb7c344dfce/thread:delegated-task:command%3Amcp%3A42e1fbbe-e54d-4e0d-8253-f080c4fbe734%3Adelegate-task%3Abookfin-boo-xyrl-astra-20261113-1>
Client request ID: `bookfin-boo-xyrl-astra-20261113-1`.

Lead: codex/gpt-6-astra xhigh. Stages: build, one read-only review
(codex/gpt-6-astra high), fixes if needed, then parent integration.
Launch reports running; branch and current stage have not yet been reported.
Parent retains integration, acceptance, hardening and closure.
