---
id: tb-0mex
status: in_progress
deps: [tb-t8rh]
links: []
created: 2026-11-10T02:33:41Z
type: feature
priority: 1
assignee: Alexis Purslane
parent: boo-fval
---
# Lay out a reflowed PDF page as lines of word images

W4 of docs/plans/pdf-word-image-reflow.md (Lines and paragraphs, Regions). Write layoutColumn(page, settings) as a pure function in a hop. It reads the geometry and the analysis, never the text. The scale from text size and body line height, wrapping in reading order, gaps, baselines (line, own, raised marks), rotation of sloped lines, line pitch, paragraphs (layout pass starts and justification, and the geometry rule), indents, centered paragraphs, justification, hyphen pairs, regions placed and scaled to fit, captions kept with their figures (keep-with-next), and screens of whole lines through a new shared pure function cutScreens(lineTops, lineBottoms, keepWithNext, screenHeight), which the text view also uses (tb-zx7r). The user settled decision 2 on 2026-11-10: design A, whole-line screens.

## Acceptance Criteria

Behavior tests, red first: words wrap in reading order and no line is wider than the column; on the skewed fixture the words of each reflowed line share one baseline within one device pixel; a raised footnote mark stays raised; paragraphs, indents, centered headings and justification follow the source; a hyphen pair on one line draws no hyphen and no gap, across two lines it draws the hyphen; regions fit the column and the screen; a figure's caption shows on its figure's screen; a size step changes word height by the size ratio; no screen cuts a line or starts with a paragraph gap; a region taller than the screen fits on one screen; a region and its caption share a screen when both fit; the column is the same with and without the text attachment.

## Notes

**2026-11-10T14:59:40Z**

From tb-t8rh: ReflowPage.geometry is the reflow geometry. It holds extra words (PageAnalysis.sourceWords is -1) inside their lines, with empty ranges and NaN own baselines. On a scanned page, a raised mark at a word's right end (footnote marks 17 to 21 of Gibbon's page, and closing quotes such as the one after 'est.') splits off as an extra word right after its word, 2 to 5 pixels away at 1600 pixels wide. If the wrap rule puts at least a third of a body line height between words, such a mark and quote move away from their word. An extra word probably keeps its source gap to the word before it. Lines that are not prose (PageAnalysis.isProse) hold region words; PageAnalysis.wordRegions names the region of each word.

**2026-11-10T15:03:43Z**

From tb-t8rh: an extra word (uncovered ink or a raised mark split off a scanned word) should keep its source gap to its neighbor, or its mark or closing quote moves away from its word.

**2026-11-10T15:31:38Z**

Built (2026-11-10). lib/reader/column_layout.dart: ColumnSettings (width, fontSize, screenHeight), ReflowColumn (pieces with source rect, target rect and rotation; lines with top, baseline, bottom; screens; checkInvariants), layoutColumn (pure, reads geometry and analysis only). lib/reader/screen_cut.dart: cutScreens, shared with the text view (tb-zx7r). ReflowPage.column(settings) runs the layout through the book's hop. Deviations are in the design doc under 'The column on the fixtures'. For tb-xjfi: a piece's image turns about its target's center; its source rectangle is in page units of the reflow geometry; a joined hyphen half already has the hyphen cut from its source rectangle; turned pieces overlap their neighbors by a fraction of a pixel, so draw with a blend that does not paint paper over ink. For tb-22fu: screens start at a line's top, and screenTop(screen) is the y to show. Found te-qg8l (missing ink in 'quaint' on the Raven page). Tests: test/reader/column_layout_test.dart, test/reader/screen_cut_test.dart.
