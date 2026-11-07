---
id: boo-bquq
status: open
deps: [boo-um68, boo-5jzo]
links: []
created: 2026-11-07T21:20:29Z
type: chore
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Bring existing widgets in line with the UI architecture rules

AGENTS.md now has UI architecture rules: data down, actions up; one component per kind of thing; minimal dependencies with low-level subscription. Known breaks: DownloadControls and row buttons call Downloads directly; the timeline calls Playback restore and delete; RecentListeningList calls playback.open; _LeftoverInventory owns a storage future in a leaf State. Audit and refactor after the current audit branches merge.

