---
id: t8-ld5q
status: open
deps: []
links: []
created: 2026-11-02T05:35:06Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Decide recovery when a downloaded source revision changes

AudioPosition.fits rejects changed or empty source revisions. Playback retains the original scoped resume and refuses to apply it; this prevents silent position reuse. Choose the user-facing recovery in the parent: (A) confirm a fresh start while retaining the old resume separately, or (B) require source-position reconciliation before playback. A immediately permits replacement playback but needs a clear fresh-start confirmation; B avoids an implicit reset but blocks listening until reconciliation exists. No recovery choice is implemented by boo-sthf. Keep this separate from live-session reporting and from claims of full personal-record sync.
