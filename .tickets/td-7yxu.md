---
id: td-7yxu
status: open
deps: []
links: [t7-msmk]
created: 2026-11-02T14:10:11Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Keep the Android fixture route observable across app relaunch

Authorized Android acceptance at main261d50e created its own reverse tcp:7365 route. Basic playback, record persistence, account isolation and retained storage were observed. After the second agent-device --relaunch the reverse list was empty, while owned loopback servers were alive; restoring library selection showed Cannot reach Jellyfin. Navigation and its advised retry then failed, so acceptance stopped. Cause of route loss is unproven. Do not infer a Bookfin networking defect or evade the stop rule. See docs/evidence/playback/current-main-android.md.

## Acceptance Criteria

Before another authorized device attempt, inspect how the normal fixture reverse route survives a T3 app relaunch. Recheck only owned route state after relaunch and stop on host/tool rules. Complete remaining replacement confirmation and personal-record interactions with public credential-free evidence.
