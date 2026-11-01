---
id: td-4nvl
status: open
deps: []
links: []
created: 2026-11-01T23:35:25Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Resolve HTML and Markdown acquisition for the reader

Upstream Jellyfin v12.4 BookResolver does not recognize .html or .md. Determine how the approved reader receives these files before promising Jellyfin discovery. Present the existing-file options to the user: explicit Android local import (no server installation, but those files are not discovered from Jellyfin), or plugin-backed permitted library discovery/download (server-side maintenance, but server-backed acquisition). Keep this separate from rendering and do not silently change the approved feature scope.

## Design

docs/plans/bookfin.md; docs/research/jellyfin.md

## Acceptance Criteria

Record the chosen acquisition boundary and security requirements; prove an HTML and Markdown file can reach the offline reader without unauthorized filesystem access or active content. Coordinate with boo-9wgg and any accepted extra-record plugin design.
