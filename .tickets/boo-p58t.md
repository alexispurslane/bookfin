---
id: boo-p58t
status: in_progress
deps: [boo-gxm8]
links: []
created: 2026-11-01T21:37:34Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
---
# Prove Jellyfin catalog media and extra-record storage

Inspect the actual Jellyfin version and representative book libraries. Test ordinary-user access, chapters, downloads, per-item progress, ebook discovery, and custom display preferences in a disposable namespace.

## Design

docs/plans/bookfin.md

## Acceptance Criteria

Record a decision for existing storage versus plugin. Prove concurrent writes, discovery, deletions, isolation, retry, size limits, and restart behavior. Do not promise full sync from a successful single-device round trip.


## Notes

**2026-11-01T23:02:12Z**

Target Jellyfin server supplied by user: https://jellyfin.example.com. Discover its version during integration. Request credentials only through T3 private secret input.

**2026-11-01T23:45:22Z**

Research head e9dacdf4698f086d2aba741e5c5da36a0b84cb97 is awaiting independent review. Public evidence reports server 12.4.0; authenticated checks remain unproven. Parent has not selected a new plugin: existing advertised JellyfinEnhanced routes must be assessed before declaring existing server capabilities inadequate. Private login requested through T3; no credentials stored in this ticket.
