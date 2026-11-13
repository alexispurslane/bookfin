---
id: boo-7z9a
status: open
deps: []
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

