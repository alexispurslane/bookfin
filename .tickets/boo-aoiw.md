---
id: boo-aoiw
status: closed
deps: []
links: []
created: 2026-11-10T01:29:54Z
type: chore
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
---
# Share one Gradle and pub cache across all checkouts

Each agent worktree kept its own .cache/gradle (3.4 GB) and .cache/pub, because the dev shell set them under $PWD. With about 95 worktrees the Mac's disk filled to 4 GB free, and an agent could not start an emulator. The dev shell now puts both under ${XDG_CACHE_HOME:-$HOME/.cache}/bookfin. Gradle and pub both lock their caches for concurrent builds.

