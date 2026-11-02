---
id: te-kzht
status: open
deps: [boo-61vt]
links: []
created: 2026-11-01T23:32:51Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
---
# Choose and implement production appearance location input

boo-61vt accepts a selected location, calculates sunlight locally, and includes explicit development city fixtures. Production acquisition remains a genuine product choice: bundled offline city picker (no permission, limited coverage) versus foreground approximate device location (broader coverage, permission/plugin/platform cost). No precise/background permission or remote lookup is authorized. Parent must obtain the narrow user choice, then implement the chosen input without copying appearance policy.

## Acceptance Criteria

User chooses the input strategy. Selected location persists through the existing appearance controller; removing it restores the explicit system fallback. Android input/permission flow is tested; no silent precise/background access or remote service.
