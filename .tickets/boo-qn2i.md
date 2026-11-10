---
id: boo-qn2i
status: in_progress
deps: []
links: []
created: 2026-11-10T22:27:15Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
---
# Use real shared History capture and Nihil Unbound PDF comparison on homepage

User requests a real app screenshot for shared History, clearer shared-history description, Nihil Unbound Original versus Page words captures, and detailed reflow bullets matching the other homepage sections. This supersedes the previous Raven comparison and illustrative timeline. Capture actual production widgets; no HTML reconstruction or retouched app contents. User authorizes a limited NU screenshot excerpt on the homepage; never track the source PDF, private server details, or unrelated personal history. Preserve existing page style and explain only implemented behavior. Parent verifies rendered result and integrates.

## Acceptance Criteria

Genuine shared History image shows listening and reading entries and controls; genuine same-source NU comparison shows useful prose reflow; detailed accurate feature bullets; phone/desktop layouts and provenance checked.


## Notes

**2026-11-10T22:28:05Z**

Continued existing Sol xhigh homepage writer. taskId node:delegated-task:command%3Amcp%3Ae6a3d378-c450-4501-a47c-77e7994db5fb%3Athread-send%3Asol-xhigh-homepage-nu-history-20261110-1; childThreadId thread:delegated-task:command%3Amcp%3Ae6a3d378-c450-4501-a47c-77e7994db5fb%3Adelegate-task%3Asol-xhigh-20261110-boo-54l1-homepage-1; clientRequestId sol-xhigh-homepage-nu-history-20261110-1. Existing branch t3/foreground-pdf-reflow fast-forwards main before work. Actual production-widget host captures, no device actions; NU source stays private and untracked, user-requested limited screenshot excerpt only. Parent inspects and integrates.

## Implementation notes — November 10, 2026

- Fast-forwarded the existing leaf branch to main at `bfcbe24b7c6ef6324c6769d02c40cf236ebd5ed0` before edits. No checkout was created, reset, or switched. No subagents or devices were used.
- Replaced the Raven homepage comparison with actual production `PdfViewport` renders of the authorized *Nihil Unbound* excerpt: PDF source page 24, printed page 9, in Original, Cream size 24, and Night size 28. Selected body prose after inspecting real captures; only one source page is published, not the source PDF or a text dump.
- Replaced the HTML history illustration and old audiobook-only image with the real production shared History sheet over `PlayerView`. Controlled River fixture records go through real Playback and ReaderSession owners; the image shows both media and expanded Go back, Go to, and Delete controls. No private history was used.
- Expanded reflow bullets in the existing dot-and-divider style. Shared History copy now names its player, reader, and book-details entry points and explains cross-medium Go to. It does not claim paired live/current resume rows, unlimited text sizes, perfect extraction, or per-book view/trim persistence.
- Kept the local fonts, cream/sepia tokens, unrelated sections, and all external download/source links. All four new captures are 822 by 1680 pixels; together they are 415,224 bytes. Lower captures load lazily and all images have dimensions and alternative text.
- Provenance and claim references: `docs/marketing/nihil-unbound/README.md`, `docs/marketing/shared-history/README.md`, their `assets.json` manifests, and `docs/marketing/boo-qn2i-verification.json`. Older Raven notes are explicitly marked historical evidence.
- Verification: two final production-widget capture tests passed; 64 existing history tests passed; markup/local assets/anchors/dimensions/claim-source paths and unchanged external links passed. All capture, encoding, and local validation commands used Nix. Targeted T3 previews at 390 light and 1280 dark loaded every image without horizontal overflow; they used fallback fonts and host theme tokens, not the final full-page font-faithful view.
- Limitations: selected page has reliable native text geometry, but trial pages 18–22 did not; no production workaround was added. Early scratch History harness attempts required clock-pumping fixes, after which the final captures passed. No full Flutter suite, coverage, mutation, device-performance, or Android UI claim is made. Parent owns the final full-page preview, integration, and ticket closure.
- Applied impeccable, software-design, PDF, and plain-English guidance. Read test-driven-development; no executable behavior changed and no HTML-string mirror tests were added. No design fork remains.
