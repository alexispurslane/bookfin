---
id: t6-epwo
status: in_progress
deps: []
links: []
created: 2026-11-07T22:41:16Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-bquq
tags: [ui-rules]
---
# AccountBinding follows the catalog's account and library signals

From t9-se8f. lib/app/account_binding.dart listens to the broad CatalogController notification and compares catalog.books by identity, so it wakes on every busy and message change. The catalog now has accountNotifier (session, access, libraries, selection) and libraryNotifier (changes only when the books change; a refresh with the same entries and corrections keeps the same library and Book objects). Move the binding to those two signals. Owned files: lib/app/account_binding.dart and its tests. Order: with or after boo-0km1, which also changes account_binding.dart.

## Acceptance Criteria

A catalog busy change and a refresh that changes no book wake no AccountBinding work (counter).

