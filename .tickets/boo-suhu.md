---
id: boo-suhu
status: in_progress
deps: [boo-mx5i]
links: [t0-qnnu]
created: 2026-11-02T00:07:18Z
type: feature
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Add bundled offline OCR for scanned PDF reading

User approved OCR for the ultimate feature set. Recognize text in scanned PDF pages locally to support reflow and search. Prefer a fast, simple engine bundled with Android; no cloud service or required first-use model download. Preserve original pages.

## Design

docs/plans/bookfin.md. Engine selection remains open; measure Android speed, memory, app size and recognition quality before choosing. Identify bundled language coverage and any optional language downloads explicitly.

## Acceptance Criteria

Demonstrate offline recognition after a fresh install on Android, reflow and search from recognized text, source-page positions, cached results, cancellable work and original-page fallback on recognition failure. Record representative scan accuracy, per-page latency, peak memory and packaged size. Document engine/model licenses and language coverage. Do not claim OCR fixes arbitrary reading order or tables.


## Notes

**2026-11-03T01:40:31Z**

Partial research-only Android measurement evidence is in tool/evidence/reader/ocr/20261102/android-device/README.md and summary.json. Verified all five APKs and source archive from 562dec2 / source 838d8a4. Baseline storage plus two actual English-fast offline reports (28 recognitions) scored with exact bundled scans/references. Fresh/repeat initialization 356.795/107.699 ms; sampled PSS maxima 269055/274751 KiB. Crop 2/31 word edits; generated English 0/37; generated French 6/40 each pass. Full pages remain unscored. Directory package+private sums 13224 KiB baseline and 28740 KiB English-fast, not complete StorageStats totals. Stopped after second bound-device wait timeout; English-best/Latin-fast/MLKit never installed. Cancellation preserved prior report; new native run and leave/reopen observed, but completed recovery not obtained, so lifecycle acceptance incomplete. Research control overlap tracked in te-bkuv. Cleanup removed both owned packages/processes, restored network to 0/1/1, retained media mute, released binding shutdown:false. Ten exact-source scorer/quality tests pass. No production OCR, PDF/MOBI/sync acceptance, license clearance, or engine/language selection. Ticket remains open/in progress; another device attempt needs explicit authorization after the stop rule.
