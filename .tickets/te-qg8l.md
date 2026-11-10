---
id: te-qg8l
status: in_progress
deps: []
links: []
created: 2026-11-10T15:31:38Z
type: bug
priority: 2
assignee: Alexis Purslane
parent: boo-fval
---
# Show the ink between two layout words of one printed word on the Raven page

In a probe render of the reflowed Raven page (tb-0mex, 2026-11-10), the word 'quaint' in 'Over many a quaint and curious' shows as 'qu' and 'int': the letters between the layout words at x 440-476 and 486-533 (y 2136-2162 at 1600 px wide) do not show. The column places every word and extra word of the reflow geometry, so the ink is probably neither in a word box nor an extra word. Find whether the page analysis drops it (word cover, speck size) or whether the ink lies outside both boxes, and make every printed mark of a line show (page analysis step 6).


## Notes

**2026-11-10T16:53:06Z**

Built (2026-11-10). Cause: the layout pass split 'quaint' into words at 440-476 and 486-533 px; the letters between them are gray (luminance 83-111 on paper 155, so 0.55-0.72 of the paper), lighter than the ink rule (below half the paper), so no component and no extra word held them, and no word box did. Fix (part of analysis step 1): _Raster.joinSplitWords joins two neighbor words of a line when their gap is narrower than the line height and every pixel column of the gap holds print (below three quarters of the paper's luminance) in the rows both words share; the first word's box grows to the second's left edge, so the column glues them. On the fixtures, only this gap joins. SurveyFiles.format is now 3. Tests: page_analysis_test 'a printed word that the layout pass splits', column_layout_test 'quaint', and the guard column_ink_test (no ink in a text line of any fixture page is left out, except rejoined hyphens). Faint edges outside word boxes: t2-bvhi.
