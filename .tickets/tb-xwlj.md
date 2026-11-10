---
id: tb-xwlj
status: open
deps: [tb-jidt]
links: []
created: 2026-11-10T02:33:41Z
type: feature
priority: 1
assignee: Alexis Purslane
parent: boo-fval
---
# Give text layer PDF pages word geometry from their character boxes

W2 of docs/plans/pdf-word-image-reflow.md (From the text layer, When the geometry is not usable). preparePdfPage also takes the page width and height and builds PageGeometry from the character boxes: words as runs without white space, boxes in page units with y flipped, own baselines from characters outside the descender set, lines, blocks, and line baselines. A candidate text layer with unusable boxes gives no geometry. Add the born-digital equation fixture, made with Typst in the dev shell from a source file kept beside it.

## Acceptance Criteria

Behavior tests, red first: each word is a run of the text without white space and its box holds its characters' boxes; lines and blocks follow the equation fixture's printed lines; unusable boxes give no geometry; a page whose text layer cannot be put in reading order still takes its words from recognition. Text and digest stay unchanged. Typst is pinned in the flake.

