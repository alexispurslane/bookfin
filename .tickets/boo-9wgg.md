---
id: boo-9wgg
status: open
deps: [boo-u3cg, boo-7o92, boo-73yj]
links: [t3-9r9u, boo-mx5i]
created: 2026-11-01T21:37:34Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Build EPUB HTML and Markdown reading

Provide contents, text sizing, themes, search, bookmarks, local assets, and stable edition-specific positions. Keep reader and audio positions separate.

## Design

docs/plans/bookfin.md

## Acceptance Criteria

Read offline on Android, reopen at the correct location, and block active or unintended remote content. Test representative books and accessibility.


## Notes

**2026-11-02T10:47:48Z**

2026-11-02 finite research continuation: unmodified EPUBX 4.0.0 cannot share a solver with pdfrx_engine 0.9.0 (image 3/archive 3 versus image 4/archive 4). A research-only, source-hash-pinned EPUBX patch updates those two ranges and adapts cover decoding to Uint8List. Five joint host checks pass, including PDF extraction in the same process, EPUB3 chapter/image parsing, EPUB2 cover decoding and all three existing MOBI conversions. See tool/research/readers/dart_compat and epubx-compat.patch. This is a concrete compatibility candidate, not package approval or an EPUB navigator. Parent must review maintenance ownership and navigation/security/accessibility/resume integration before production selection.

**2026-11-02T11:14:09Z**

Android follow-up now confirms the research-only EPUBX compatibility patch runs with pdfrx 2.11.0 in one app process and with no INTERNET permission. Generated EPUB and MOBI6 text/PNG previews display. Standalone KF8 text also displays, but its first image is SVG (OEBPS/flow00004.svg, 324 bytes), so Flutter Image.memory reports Invalid image data. t3-9r9u records this precise presentation failure. The preview also flattens heading/paragraph boundaries. No production navigator or package approval is implied.
