---
id: tb-nkz5
status: in_progress
deps: [tb-valc]
links: []
created: 2026-11-10T12:53:21Z
type: feature
priority: 1
assignee: Alexis Purslane
parent: boo-fval
---
# Add a Trim margins switch to the PDF Reading settings

T4 of docs/plans/pdf-word-image-reflow.md (Trimmed margins: The switch). A Trim margins switch in the glass Reading settings sheet, shown only for PDFs, on by default. Off shows the full printed page in the Original view. ReaderSession keeps it and saves it with the text size, so it lasts across runs. The word view always drops headers and folios, whatever the switch says.

## Acceptance Criteria

Behavior tests, red first: the switch shows only for PDFs and is on in a new install; turning it off shows the full page at once, and on shows the crop at once; the choice survives a restart; the word view is the same with the switch on or off; the sheet stays glass and the row stays usable at the largest system text size.


## Notes

**2026-11-10T19:28:22Z**

Sol xhigh lead launched. taskId: node:delegated-task:command%3Amcp%3Ae6a3d378-c450-4501-a47c-77e7994db5fb%3Adelegate-task%3Asol-xhigh-resume-20261110-tb-nkz5-1; childThreadId: thread:delegated-task:command%3Amcp%3Ae6a3d378-c450-4501-a47c-77e7994db5fb%3Adelegate-task%3Asol-xhigh-resume-20261110-tb-nkz5-1; clientRequestId: sol-xhigh-resume-20261110-tb-nkz5-1. Base f674c7b includes reviewed crop implementation. Fresh Sol xhigh reviewer required.
