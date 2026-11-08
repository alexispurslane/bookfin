---
id: td-vjzg
status: open
deps: []
links: []
created: 2026-11-08T21:18:48Z
type: bug
priority: 3
assignee: Alexis Purslane
parent: boo-b2ey
---
# Keep U+FEFF in contents titles, as epub.js does

Publication.contents folds U+FEFF (zero width no-break space) in a contents title to a space. epub.js keeps it. So the chapter label of a native page or search hit differs from the WebView's label where a title holds U+FEFF. In the trial books only three titles of se-poetry have one ('To —﻿—﻿—'): 47 page records (tc-sqp7) and 53 search hits (tc-866u) show 'To — — —' where the WebView shows the title with U+FEFF. Contents are beside the publication identity, so a fix does not move saved places. When it is fixed, remove the U+FEFF fold from the reader.js fixture note in test/reader/epub/search_test.dart and re-record the se-poetry digests.

## Acceptance Criteria

The chapter label of every search hit and page start in se-poetry equals the label that reader.js gives. The publication identity of every fixture book stays the same.

