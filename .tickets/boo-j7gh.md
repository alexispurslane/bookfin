---
id: boo-j7gh
status: open
deps: []
links: []
created: 2026-11-12T23:41:02Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Count visible book characters with one walker and measure the outline once

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: confirmed. lib/speech/book_words.dart:94-164 and lib/reader/book_map.dart:528-531 each walk a section and count visible characters, and the two counts must agree to the character. Only one fixture test compares them. A change to what counts as visible in one walker moves every speech landing silently. `BookWords` also calls `measureTextOutline` again, though Crossings already holds that outline. Use one walker that yields each text run with its visible offset, and pass the kept outline into the read job.

