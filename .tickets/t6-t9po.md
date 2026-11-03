---
id: t6-t9po
status: open
deps: []
links: [boo-3oq0]
created: 2026-11-02T23:08:38Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Bound production sync journal growth without discarding unsynced records

Production personal-record sync retains immutable operations, including superseded resume updates. Add a durable equivalent checkpoint or safely staged unsent resume representation, with causal-gap/retry/deletion/restart tests, before claiming lifetime storage bounds. Do not expire listening history. Coordinate this with boo-3oq0; no competing hardening job.

