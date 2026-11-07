---
id: t4-lvhh
status: closed
deps: [t6-2ghu]
links: []
created: 2026-11-07T22:48:59Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-bquq
tags: [ui-rules]
---
# The catalog status says whether the last sign-in or refresh succeeded

From t6-epwo. AccountBinding asks record sync to run when CatalogController.verified is true. No narrow signal holds verified. It turns true only at the end of a sign-in or refresh that succeeded, and that end always changes statusNotifier (refreshing goes from true to false), so AccountBinding reads catalog.verified when statusNotifier, accountNotifier or libraryNotifier changes. lib/catalog/library_view.dart also reads verified (boo-0km1 removes that use). Add the value to CatalogStatus (lib/catalog/controller.dart), or show that reach == reached with refreshing false states the same fact, so that AccountBinding reads only signal values and t9-cx1u can drop the getter. Owned files: lib/catalog/controller.dart, then lib/app/account_binding.dart.

## Acceptance Criteria

AccountBinding decides on record sync from statusNotifier's value alone; the account_binding tests about synchronize still pass.

