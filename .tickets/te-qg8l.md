---
id: te-qg8l
status: open
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

