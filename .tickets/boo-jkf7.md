---
id: boo-jkf7
status: open
deps: []
links: []
created: 2026-11-07T20:55:42Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Reduce blur and image decode cost

Audit P10, P11: each glass pane stacks BackdropFilter, ImageFiltered and Opacity, and redraws at 5 Hz under the ticking player; covers decode at 540 px even in 36 px rows. RepaintBoundary around the slider, drop the Opacity saveLayer, blur a tiny decoded cover, add a cover size class to the cache key. Profile first.

