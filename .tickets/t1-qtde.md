---
id: t1-qtde
status: open
deps: []
links: []
created: 2026-11-08T23:49:54Z
type: bug
priority: 2
assignee: Alexis Purslane
parent: boo-b2ey
---
# Find a paragraph's line starts in one pass, not one engine call per line

Found in tc-4f3q (corpus run). LayoutRun._lineStarts (lib/reader/epub/layout.dart) calls Paragraph.getLineBoundary once per line, and getLineNumberAt once more per line. In the Flutter engine, getLineBoundary builds the metrics of every line of the paragraph on each call (flutter::Paragraph::getLineBoundary -> txt::ParagraphSkia::GetLineMetrics). So the line starts of a paragraph with n lines cost on the order of n squared line metrics. A run that resumes inside a paragraph pays it again.

Seen with macOS sample on the corpus run: while it checked Gutenberg's Leaves of Grass (section ..._1322-h-26.htm.xhtml, 91,000 characters: Song of Myself in three pre elements, so each is one paragraph with thousands of hard line breaks), 98 percent of the main thread's samples were in flutter::Paragraph::getLineBoundary. Long verse paragraphs and long prose paragraphs are common in the corpus, so this is the main layout cost of such sections on the UI isolate.

## Acceptance Criteria

- The line starts of a paragraph come from one pass over its line metrics (for example computeLineMetrics once, then getPositionForOffset or glyph lookups per line start), with the same results as today, including the rule that a hard break's newline belongs to the line that it ends.
- A test holds the line starts of a paragraph with hard breaks, soft wraps and a trailing break against today's values.
- The corpus run's slow-item list for Gutenberg's Leaves of Grass shrinks, with numbers in docs/research/native-epub-corpus.md.


## Notes

**2026-11-09T01:51:10Z**

Corpus numbers (host JIT, machine load 10 to 40 on 10 cores, so absolute times are high): one layout step of the Song of Myself pre paragraph (Gutenberg Leaves of Grass, section 27) takes 1,580 ms at 412 x 671 at 20 pixels and 3,593 ms at 360 x 640 at 26 pixels. The index of Gutenberg's Origin of Species (section 17, one paragraph of short lines) takes 508 ms and 605 ms. The longest paragraph steps of both Divine Comedy editions (verse with br elements) take 30 to 100 ms. The paragraphs with many lines lead the slow-item list of .cache/epub-corpus/results.json. Roget's Thesaurus (one 1.74-million-character table) spent its time in getLineBoundary too, so this and t1-um08 together decide its cost.

**2026-11-09T02:26:01Z**

More corpus numbers: Gutenberg's Hong Lou Meng (Chinese, long paragraphs that wrap into many lines) has paragraph steps of 1,117 to 1,677 ms at 412 x 671 at 20 pixels and up to 1,723 ms at 360 x 640 at 26 pixels, and the highest layout time per 10,000 visible characters at 20 pixels (74 ms, against a corpus median of 10 ms). The Kindle conversion of Leaves of Grass repeats the Song of Myself numbers (1,566 and 3,161 ms).
