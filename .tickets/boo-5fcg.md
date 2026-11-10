---
id: boo-5fcg
status: closed
deps: []
links: []
created: 2026-11-10T19:33:10Z
type: bug
priority: 1
assignee: Alexis Purslane
parent: boo-fval
---
# Make cropping ready promptly for Nihil Unbound on Pixel 8

User reports no visible crop after installing 2a73abc. On-phone kept survey has 14 analyzed pages and no profile, so Original remains whole. Trace survey progress and failures on the actual 290-page PDF; distinguish slow initial sampling, permanently skipped sample slots, and viewport application. Preserve printed content and existing reading records. Record real device evidence and a regression for any code defect.


## Notes

**2026-11-10T19:35:11Z**

Confirmed on actual 290-page PDF with host probe .cache/crop-diagnosis/nihil_probe_test.dart and private local fixture /tmp/bookfin-nihil-unbound.pdf (do not commit it). Source pages 11 and 14 have PdfTextStatus.candidate but geometry null. Page 11 is therefore absent from the on-phone survey even after profile freeze. The early survey had 14 pages/no profile; about two minutes of foreground reading later it had 76 pages/profile present. Source page 12 visibly crops after a turn. _NativePdfBook.geometry returns layer.words?.geometry immediately for candidate text, so valid text plus rejected word geometry has no fallback. Investigate rejection cause and retain usable text/places while supplying valid geometry. Initial survey latency is a separate observation, not proof of a stalled queue.

**2026-11-10T19:35:59Z**

Sol xhigh lead launched. taskId: node:delegated-task:command%3Amcp%3Ae6a3d378-c450-4501-a47c-77e7994db5fb%3Adelegate-task%3Asol-xhigh-20261110-boo-5fcg-1; childThreadId: thread:delegated-task:command%3Amcp%3Ae6a3d378-c450-4501-a47c-77e7994db5fb%3Adelegate-task%3Asol-xhigh-20261110-boo-5fcg-1; clientRequestId: sol-xhigh-20261110-boo-5fcg-1. Private actual-PDF verification plus synthetic regression; parent owns phone verification.

**2026-11-10T19:50:49Z**

Root cause: valid extracted text includes invisible printing labels above the visible PDF page. Native character boxes on source pages 11 and 14 extend to about 609-615 PDF points above a page only 583.937 points high. The prior all-or-nothing word builder rejected the entire page. Fix: pageGeometryFromCharacters owns visible-word geometry and the matching original source ranges together. It leaves out only whole, finite, positive-area word boxes wholly outside the page, retains all extracted text/source offsets/digests, and still rejects malformed boxes, edge-crossing visible words and implausibly tall words. No recognition fallback, crop sampling or saved-address changes are needed for this cause. Four synthetic edge regressions failed with null geometry before the implementation. Existing rejection/digest tests stay intact. A synthetic native rotated page exposed an unsafe coordinate-frame case: pdfrx gives unrotated boxes with rotated dimensions. A separate red regression now preserves the documented no-text-layer-geometry behavior for rotated pages without changing their text. Follow-up t6-chz6 tracks proper rotated geometry. Focused geometry/text/analysis/crop/template/column tests plus the private host probe passed 74/74. Private source pages 11 and 14 now have 329 words/35 lines and 129 words/14 lines, respectively, with complete matching attachments, valid analyses, preserved character addresses and crops that hold all content. No private text or PDF is tracked. The private probe stays ignored under .cache/crop-diagnosis. Phone verification belongs to the parent. Required checks and fresh review are still pending.

**2026-11-10T19:53:53Z**

Required validation passed on 2026-11-10: dart format --output=none --set-exit-if-changed lib test tool integration_test checked 390 files with zero changes; flutter analyze lib test integration_test found no issues; full flutter test --reporter expanded passed 2521 tests with 21 skipped in 2m22s. The known boo-7plj survey-resume failure did not recur, and is not claimed fixed here. Flutter emitted missing iphoneos/iphonesimulator SDK warnings on this Android-focused host. No native implementation changed, so native/ocr_worker checks are not required. Fresh Sol xhigh read-only review follows this build commit. Coverage and mutations remain with the parent.

**2026-11-10T20:04:15Z**

Fresh read-only GPT 6.1 Sol xhigh review of b7cb46d..ec1e04a passed correctness, fulfillment and software design separately, with no findings. Reviewer task: boo-5fcg-fresh-sol-xhigh-review-20261110-1. Closed its additional evidence gap after review: the ignored host probe now reads the copied phone survey-later frozen profile, not a generated per-page profile. The source 11 and 14 geometry, matching text attachments, analyses and saved character addresses pass invariants; both cropOf results hold all detected content and are narrower and shorter than the whole page. Source 11 crop: left 0.0662499992, top 0.0693749962, right 0.9325000169, bottom 1.5631249668. Source 14 crop: left 0.0674999980, top 0.0693749962, right 0.9343750002, bottom 1.5693749906. Coordinates use page-width units, with the origin at the top left and y growing down. The copied surveys have 14 pages/no profile, 54 pages/no profile, then 76 pages/profile present; all omit source 11. Sources 12 and 13 retain unreliable text-layer status, so their existing Android layout path is untouched. Evidence: /tmp/bookfin-5fcg-phone-profile-verification.log, one host test passed. No phone or emulator was used. Pixel acceptance, proper rotated geometry (t6-chz6), sampling-latency measurement, coverage and mutations remain with the parent. Integration points: pageGeometryFromCharacters in page_geometry.dart now returns geometry and original character ranges as one record; preparePdfPage consumes that record; _NativePdfBook._layer rejects geometry for rotated native coordinates but preserves text. No other pdf.dart methods, column layout, word pages, viewport or settings changed. This final commit changes ticket notes only; reviewed production and committed test sources remain ec1e04a.

**2026-11-10T20:06:37Z**

Parent inspected extraction changes, safe rejection, native rotation guard, synthetic regressions and fresh review. Integrated with Trim margins and survey-test fix; only conflict was ticket notes, both retained. Combined geometry/reader suite plus actual private PDF probe passed; source 11 now has 329 words and source 14 has 129 words, both analyze successfully. Phone verification follows.

**2026-11-10T20:08:22Z**

Parent integrated as b901b6c; 131 combined geometry/reader tests passed, including actual private PDF probe. Normal ARM64 debug APK built with native/OCR/signature/alignment verification and installed successfully in place on Pixel 8. On-phone visual crop check is pending: user was actively in another app, so parent stopped screen interaction and requested a convenient time. No private book text or screenshot added to repository.

**2026-11-10T20:09:19Z**

User chose to test the installed update themselves. Parent will perform no further phone interaction for this check. Installed base.apk SHA-256 exactly matches built APK: aaff40dd2354e6fa926976d4aa45af157fe06cfefaea678f7b2921ef11ee35bd. Code integrated and host verification complete; physical reading acceptance remains user-owned and part of tb-fb6j.
