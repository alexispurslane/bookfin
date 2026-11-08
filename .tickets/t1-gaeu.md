---
id: t1-gaeu
status: open
deps: []
links: []
created: 2026-11-08T00:06:43Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-bquq
tags: [engine-rules]
---
# A pull to refresh during a background refresh reports that refresh's failure

At boo-0km1, LibraryShelf's pull to refresh does nothing while a refresh runs (catalog.busy). A background refresh at launch or resume keeps a failure after Jellyfin answered silent (refresh(byUser: false)). So if the person pulls while a slow background refresh runs, and that refresh then fails with an incomplete catalog or a save failure, nobody tells them. An unreachable Jellyfin is shown in every case, from CatalogStatus.reach.

Options: the pull marks the running refresh as asked for, so that the controller reports its failure; or the pull restarts the refresh with byUser: true. Owned files: lib/catalog/controller.dart, lib/catalog/library_view.dart and their tests.

## Acceptance Criteria

A pull during a running background refresh that then fails after Jellyfin answered shows the failure. A pull during a refresh starts no second request.

