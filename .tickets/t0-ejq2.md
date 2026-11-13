---
id: t0-ejq2
status: open
deps: [boo-39cu]
links: []
created: 2026-11-13T23:20:24Z
type: bug
priority: 3
assignee: Alexis Purslane
parent: boo-fs0n
tags: [error-handling, follow-up]
---
# Propagate programming errors from the audio place-origin lookup

Recorded during boo-39cu in the pre-existing Playback._open origin lookup: store.origin(...).then(... onError: (Object _) => null) converts every failure, including programming Errors, to unknown place origin. The scoped removal changes do not add this behavior. Distinguish expected storage Exceptions from programming Errors while retaining concurrent decoder loading and preventing an unhandled future before the origin is awaited. This is a static finding, not a runtime reproduction.

## Acceptance Criteria

A controlled origin Exception can remain unknown origin; an Error reaches the owning command or zone unchanged. Preserve Ask-at-Play, external Play and held-load record tests.
