---
id: td-4nvl
status: closed
deps: []
links: [ta-qobz]
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

## Notes

**2026-11-02T00:19:35Z**

Authenticated read-only investigation on November 1, 2026 (America/New_York; November 2 UTC) found one visible books library with 1,485 AudioBook entries and zero indexed Book entries. No ebook pairing or HTML/Markdown bytes were obtained. Served OpenAPI advertises item-ID-based /Items/{itemId}/File and /Download, but no named HTML/Markdown acquisition route among inspected book/file/download/attachment routes. Jellyfin Enhanced 12.14.0.0 bookmark/settings routes do not provide library-file acquisition. This is not evidence that sidecar files do not exist on disk. See docs/research/jellyfin.md for the final broader type counts. Keep the acquisition decision open; do not silently choose local import or a plugin.

**2026-11-02T13:40:10Z**

User explicitly removed HTML and Markdown from product scope on2026-11-02. Close as scope removed, not as implemented acquisition. No local-import or plugin file-discovery work is authorized or needed for these formats. Preserve historical research as historical evidence.
