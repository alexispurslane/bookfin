---
id: tb-5fyd
status: closed
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

## Notes

**2026-11-02T05:28:20Z**

Finite candidate evidence is now in docs/research/jellyfin-finite-checkpoint.md and finite-model-costs.json. The two fixed research identities are retained with no expiry and unresolved conflicts preserved. Missing earlier actions never advance accepted coverage. Covered retries cannot restore the deleted bookmark after physical old-object removal. This particular candidate still stores a deletion witness per deleted record: create/delete 1,000 distinct records with every action covered leaves zero live records but 153,961 checkpoint-state bytes. Withhold device-a:1 and deliver device-a:2..1001: 1,000 buffered actions, coverage0/0, 134,854 state bytes. These are model results, not server limits or a proof that better summaries are impossible. Separate this engineering compression gap from any necessary product retention/recovery decision. No history duration, device expiry, action discard or production conflict behavior was selected.

**2026-11-02T12:05:49Z**

User selected history retained until explicit deletion on 2026-11-02. No automatic expiry or unsynced-action loss is authorized. This settles the product retention policy. Compression, deletion protection and long-offline recovery remain engineering obligations of dedicated-storage proof and production sync, not grounds to silently expire data.
