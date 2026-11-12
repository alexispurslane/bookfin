---
id: t2-ji9u
status: open
deps: []
links: []
created: 2026-11-12T01:24:34Z
type: chore
priority: 3
assignee: Alexis Purslane
parent: boo-z3is
---
# Give Crossings one owner of keyed run-once work

Crossings has three hand-written run-once caches: _pairs/_done, _outlines/_outlineWork, and _heard/_heardDone. Each repeats 'future in flight, result kept, identical() check, forget to retry', and each handles failure in its own way; that difference caused the review's B3, where a failed speech result stayed kept. Factor one small owner of keyed run-once work with one failure rule (an Exception refuses this time, a bug is forgotten and rethrown) and use it for all three. Found in the boo-vh77 review (D2).

