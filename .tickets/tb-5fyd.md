---
id: tb-5fyd
status: open
deps: []
links: [tb-887c, t3-7fv1]
created: 2026-11-02T02:39:05Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
---
# Decide history retention and long-offline replica recovery

Storage-independent product decision found during t3-7fv1. Decide user-visible history retention and any recovery policy that discards or changes admission of pending actions, once engineering evidence establishes the alternatives. A replica is one app installation with durable operation numbering. Retention must bound protocol overhead without forgetting deletion protection. Neither private playlists nor a small plugin removes this decision.

## Design

docs/plans/bookfin.md; docs/research/jellyfin-playlist-protocol.md

## Acceptance Criteria

Before requesting a choice, distinguish compact protocol summaries from retained user-visible history and prove the finite candidate with two fixed device identities, no automatic expiry, and unresolved conflicts preserved. These are research conditions, not production limits. Record any necessary user-visible retention or recovery choice with measured costs. No expiry, device cap, silent action loss, or new conflict policy is invented. This ticket gates production sync only; it does not block t3-7fv1 research or the listening path.
