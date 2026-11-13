---
id: te-6j4k
status: open
deps: [boo-s11s]
links: [t4-kdc8, boo-s11s]
created: 2026-11-13T04:55:10Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Admit received record pages without repeated JSON work on the UI isolate

Found while implementing boo-s11s. Transport now encodes upload snapshots, validates batch replies and decodes discovery payloads in workers, and native HTTP request encoding also uses a worker. LocalResumeStore.receivePage still calls RecordJournal.receive, which defensively JSON-copies and validates each admitted action on the UI isolate; RecordDatabase.encodeCommitWithMetadataText JSON-encodes additions there again. This is existing admission/storage work amplified by larger pages. Preserve the single durable owner, atomic page/cursor transaction, all actions, causal gaps and invalid-input guards while removing repeated JSON work. Do not copy/replay the entire retained journal on each page or expand boo-s11s into the deferred journal ownership redesign. No Android frame measurement was made.

## Acceptance Criteria

Show actual store usage and malformed-page rollback tests; move admission/commit payload CPU work off the UI isolate without whole-retained-history work per page; measure host work and Android separately.
