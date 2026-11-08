---
id: t1-vvck
status: closed
deps: []
links: []
created: 2026-11-08T00:06:43Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-bquq
tags: [engine-rules]
---
# Refresh the catalog when the app returns to the screen

The user's decision of November 7, 2026 (boo-0km1): the next refresh that reaches Jellyfin, for example on app resume, brings the full library back after Jellyfin could not be reached. At boo-0km1, lib/main.dart _BookfinAppState.didChangeAppLifecycleState reports resume to record sync, Downloads and appearance, but not to the catalog. So a library that shows only downloaded books stays so until the person pulls to refresh or taps Retry.

Target: on resume after the app was hidden (not after inactive only, such as the notification shade, to match record sync), the root calls catalog.refresh() as a background refresh (byUser stays false), unless a refresh already runs (statusNotifier.value.refreshing), so that a resume never cancels a sign-in or a refresh that the person asked for.

Owned file: lib/main.dart and its test.

## Acceptance Criteria

A resume after the app was hidden starts one background catalog refresh. A resume after inactive only starts none. A resume while a refresh or sign-in runs starts none. A test drives the lifecycle with a fake catalog client.

