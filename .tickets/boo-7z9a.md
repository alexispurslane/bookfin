---
id: boo-7z9a
status: in_progress
deps: [boo-jlhy]
links: [td-6hd7, boo-8xyn]
created: 2026-11-12T23:41:00Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Store the catalog corrections and hidden libraries of the user outside the server catalog cache

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: confirmed. `CatalogCache` (lib/catalog/store.dart:33-53) holds the entries of the server together with the edits of the user (book links, recording links, book details, file orders) and the hidden libraries. A refresh carries them forward only from the in-memory cache (lib/catalog/controller.dart:657-676), so any refresh that runs while the cache is null drops them. td-6hd7 is one instance. Each correction also decodes, digests, encodes and rewrites the whole catalog (controller.dart:820-852). Put the choices of the user in a small atomic store of their own. The server catalog becomes a derived cache that can be dropped, and the build takes both as inputs. This makes the td-6hd7 class of bug impossible.


## Astra implementation scope

Atomic catalog files from boo-jlhy are integrated and verified (3,252 passes, 25 skips). Build the ticket's settled model: durable account-scoped user corrections and hidden libraries have their own small atomic store; the server catalog is a replaceable cache, and library construction takes both. Preserve legacy choices before removing them from old catalog files or preferences. A missing, damaged or refreshed server cache cannot erase saved choices. Existing unreadable legacy catalog text must be kept aside and reported before replacement; td-6hd7 tracks that linked behavior and depends on this work. The parent will assess both tickets for closure.

Implementation and direct fixes: codex/gpt-6-astra with reasoningEffort xhigh. Exactly one fresh read-only reviewer: same model, high. Required evidence includes real-file reopen/migration/failure ordering, account isolation, corruption preservation, refresh/edit races, no full catalog persistence for a small correction, all catalog/app/durability tests, affected analysis and full Flutter suite at concurrency two. Preserve one-hour freshness, unchanged-content reuse and narrow signals. No sync format changes, device work, coverage, mutation, deployment or closure by the child.

## Delegated task

Original base: 515f431c6d26797a6c1f511b26769cbd373174a3.
Client request ID: bookfin-boo-7z9a-astra-20261113-1
Task ID: node:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-boo-7z9a-astra-20261113-1
Child thread ID: thread:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-boo-7z9a-astra-20261113-1
Thread: <t3-thread://v2/38d3e8fa-8572-4c2a-8a3b-2eb7c344dfce/thread:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-boo-7z9a-astra-20261113-1>
Launch returned running on codex/gpt-6-astra with reasoningEffort xhigh. Stage and branch not yet reported. Completion delivery is automatic.
