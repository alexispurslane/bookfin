---
id: t5-haqt
status: open
deps: []
links: []
created: 2026-11-08T22:24:58Z
type: task
priority: 3
assignee: Alexis Purslane
parent: boo-b2ey
---
# Find why Keats' poetry section breaks 21 pages where Chromium does not

After tc-n6wv (exact line positions), body text page starts in test/reader/epub/fidelity_test.dart are 1,461 of 1,482 at 20 px and 2,024 of 2,048 at 23 px. Se-poetry section 2 holds 21 of the 21 differences at 20 px, so rounded line heights were not their cause. First difference at 20 px: the page that starts with the heading 'Spenserian Stanzas on Charles Armitage Brown'. Native layout puts the heading (2 lines, 99 px), a 90 px gap, and 14 verse lines through 651 px. epub.js broke one line earlier, before the second line of the last verse, which violates widows. Chromium is at /Applications/Chromium.app: measure the heading, the gap and the verse lines there to find which part is taller.

