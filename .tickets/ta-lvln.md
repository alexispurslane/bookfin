---
id: ta-lvln
status: open
deps: []
links: []
created: 2026-11-08T16:25:48Z
type: feature
priority: 3
assignee: Alexis Purslane
parent: boo-fs0n
---
# Mark the version that this phone saved in a sync choice

Both approved mockups (docs/mockups/personal-records-a.html and -b.html) label this phone's version 'Pixel 7a · this phone', and the player pill names only the other device's place ('Pixel 8 saved 4:12:47'). The labels from boo-cows (lib/sync/labels.dart) name each version by its device name or save time, and nothing tells which version is this phone's: RecordJournal knows its own replica, but LocalResumeStore.conflicts does not say it. boo-vtvp and boo-rabw built the page and the alert without it, so the columns show only the device name and the player pill says 'Saved places differ'. Found on 2026-11-08.

## Acceptance Criteria

A choice marks the version that this phone saved as 'this phone'; the player pill names the other version's device and time; tests cover a choice with and without a version of this phone.

