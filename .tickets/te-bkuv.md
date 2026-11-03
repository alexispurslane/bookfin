---
id: te-bkuv
status: open
deps: []
links: []
created: 2026-11-03T01:33:35Z
type: bug
priority: 2
assignee: Alexis Purslane
parent: boo-suhu
---
# Keep research OCR Run control outside Android system bars

On API 36 emulator-5554, completing the pinned 838d8a4 English-fast research probe places the Run button at screen y=24..150. Its accessibility center y=87 is under the system status bar and bound agent-device semantic presses leave the report unchanged. A screenshot and UI bounds are retained in tool/evidence/reader/ocr/20261102/android-device/. A bound press at (540,140) starts a run. This is research-only control geometry, not production OCR.

## Acceptance Criteria

On the same Android configuration, fresh-launch and post-report Run and Cancel controls are fully outside system bars; bound semantic presses start or cancel exactly one run. Preserve research-only separation and do not choose a production engine.
