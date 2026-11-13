---
id: t9-ftlz
status: open
deps: []
links: [boo-hwoz]
created: 2026-11-13T16:04:25Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Move large collection result processing off the UI isolate

Review finding D1 from boo-hwoz at 5055f01314fe443e255efd14fbda49df282304dd. lib/catalog/jellyfin.dart:_collectionItems accumulates every page, then _collections reduces complete discovery and child results synchronously. CatalogController calls client.catalog before its catalog-worker handoff. Transport offloads large JSON decoding but returns maps to the UI isolate, which draws frames and handles input. The accepted count permits one million records per listing and up to eight collection-child reads concurrently; 200-item network pages do not bound the final whole-list reduction. Move large collection processing off the UI isolate while preserving request ownership and cancellation. This is static structural evidence; runtime cost is unmeasured and it does not explain tf-il7u. AGENTS.md permits recording a follow-up for touched-code engine violations. This ticket records the reviewer-authorized deferral rather than claiming the CPU work is fixed.

## Acceptance Criteria

Large collection discovery and membership reductions execute away from the UI isolate, with meaningful behavior evidence and any performance measurements reported with limits. Preserve direct membership, both source-supported Jellyfin paging shapes, deduplication, optional-metadata fallback, account/credential/cancellation guards and bounded requests. Keep current refresh cadence, no retained membership cache, and the existing catalog-worker retention model unless separately authorized. Preserve all boo-hwoz loopback fixtures and run focused and affected checks through Nix. Do not weaken timing thresholds or infer the cause of tf-il7u.
