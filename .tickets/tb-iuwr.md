---
id: tb-iuwr
status: open
deps: []
links: []
created: 2026-11-07T23:46:37Z
type: task
priority: 3
assignee: Alexis Purslane
parent: boo-bquq
tags: [ui-rules]
---
# Glass panes depend only on the playing book of CoverScope

Rule: UI rule 3 (depend on the minimum). t9-sspn made CoverScope an InheritedModel with the aspects CoverAspect.covers and CoverAspect.playing. lib/catalog/glass.dart, CoverGlass.build, still calls CoverScope.of(context) without an aspect, so a glass pane rebuilds when the cover store or the account changes too. Its CoverBlur already depends on the covers aspect alone. Change the call to CoverScope.of(context, CoverAspect.playing).

## Acceptance Criteria

A change of the cover store or the account rebuilds no glass pane whose book did not change (rebuild counter in test/catalog/book_cover_test.dart).

