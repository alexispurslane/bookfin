---
id: boo-5fcg
status: in_progress
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
