---
id: boo-6bge
status: open
deps: [t1-dth0, boo-xyrl, boo-39cu]
links: [boo-xyrl, boo-39cu]
created: 2026-11-14T00:27:26Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
---
# Accept current-account Clear data and deferred audiobook removal on Android

Native acceptance retained from integrated boo-xyrl and boo-39cu. Host tests use real local downloads and preferences/SQLite records, but the decoder boundary is a test double. Android screen inspection remains blocked by t1-dth0 after two failures in the authorized attempt. Do not retry or bypass the Device panel failure until access is restored. Parent owns acceptance; no acceptance delegate is running.

## Design

docs/plans/bookfin.md, Library redesign: current-account Clear data and save-before-removal after pause or book switch.

## Acceptance Criteria

Record installed source/APK identity. With synthetic accounts and downloaded audiobooks, confirm removal keeps multi-part audio playing through seeks and track progression; explicit pause, headset/lock-screen pause and book switch save the confirmed place before files disappear. Pending status and duplicate controls must match the actual removal. Check normal and retained downloads. For Settings Clear data, confirm only the current account is cleared after required record uploads, while personal records, other accounts, login and appearance remain. Verify Clear data waiting through a book switch, interrupted/failed saves and uploads using controlled fixtures, retry, account/source replacement, and restart during a pending operation. Record decoder/file-release behavior, History and saved places, screenshots, tool failures and unavailable cases. Host callback tests do not establish native acceptance. Use the owned T3 device session and bound command; no bypass of t1-dth0.
