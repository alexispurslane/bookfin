---
id: boo-gxm8
status: in_progress
deps: []
links: []
created: 2026-11-01T21:37:34Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
---
# Set up Nix Flutter Android and shared T3 testing

Provide a pinned dev shell and Android SDK discovery for the T3 device host. Register working T3 run/test scripts. No global toolchain installation. Resolve the missing command-line tools reported during planning.

## Design

docs/plans/bookfin.md

## Acceptance Criteria

Build and test via nix develop. Open Android through device_list/device_open. Demonstrate state-preserving hot reload and shared phone interaction. Confirm browser preview and phone access independently.

