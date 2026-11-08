---
id: tf-uoyw
status: open
deps: []
links: []
created: 2026-11-08T16:27:49Z
type: task
priority: 3
assignee: Alexis Purslane
parent: boo-fs0n
tags: [platform, macos]
---
# Keep the macOS sign-in readable after a rebuild without a keychain dialog

The macOS app keeps its session and device id in the login keychain (MacOsOptions useDataProtectionKeyChain: false), because the data protection keychain needs a keychain-access-groups entitlement and so a signing team. A locally built app is ad-hoc signed, and each rebuild of the runner changes its signature. The login keychain then shows a dialog before the new build reads the item, and the app waits at launch until the user answers. tool/bookfin accept-macos deletes the two test items before it runs for this reason. Fix: sign with a stable identity (an Apple Development team, or a local self-signed code signing certificate), then decide whether to move to the data protection keychain. This is the user's choice of signing account. Found in boo-gnx9.

## Acceptance Criteria

A rebuilt macOS app starts signed in with no keychain dialog.

