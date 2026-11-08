---
id: ta-4fhn
status: open
deps: []
links: []
created: 2026-11-08T15:43:56Z
type: task
priority: 3
assignee: Alexis Purslane
parent: boo-fs0n
---
# Give the bookmarks of a sync choice the real book title and edition label

LocalResumeStore.resolve (lib/playback/store.dart) saves each kept listening place as a bookmark with bookTitle 'Saved listening place' and editionLabel 'Saved recording', because a resume record holds neither. Since boo-cows the Personal records page knows the book and edition through labelConflict, so the choice can pass them up with the bookmark titles. Found during boo-cows on 2026-11-08.

