---
id: boo-mx5i
status: open
deps: [boo-9wgg, t9-26f6]
links: [boo-73yj, t3-ipk1, t3-9r9u, boo-9wgg, t0-odcl, t0-qnnu, t0-ebxa]
created: 2026-11-01T21:37:34Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Add supported MOBI and PDF reflow reading

Integrate the validated MOBI path and PDF original-page/reflow views. Preserve source-page links and describe unsupported document cases.

## Design

docs/plans/bookfin.md

## Acceptance Criteria

Supported sample corpus passes on Android. Reflow wraps extracted text to width. Scanned and complex documents use an explicit fallback or the separately agreed OCR path.


## User acceptance and OCR follow-up

The user accepted the displayed sample reflow output as reasonable. This is sample acceptance, not Android runtime validation or a picture-placement decision. Bundled offline OCR is now approved ultimate scope in boo-suhu, which depends on this ticket. Preserve source-page access and positions for that extension.

## Notes

**2026-11-02T11:14:09Z**

Finite November 2 proof advances the runtime prerequisite without choosing production dependencies: Android original PDF pages, fixed-size real text reflow with source-page return, scan fallback, and three local MOBI conversions now execute. Keep t3-9r9u (KF8 SVG resource presentation) and t3-ipk1 (LGPL redistribution/replacement demonstration) explicit during integration. EPUBX patch proves parser compatibility only. Source rectangles are recorded in evidence; exact-region highlighting and persisted reflow resume are not proved.
