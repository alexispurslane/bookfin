---
id: t0-9nyn
status: open
deps: [t0-4qhe]
links: []
created: 2026-11-09T21:19:35Z
type: task
priority: 2
assignee: Alexis Purslane
parent: t0-t799
---
# Highlight the spoken sentence and word on the page

ReadAloud publishes the spoken sentence and word ranges as a narrow listenable. EpubViewport draws a sentence band and a word mark under the text with the selection's line geometry, repainting only the overlay. Word times come from the segment's timing table by binary search on the player position.

