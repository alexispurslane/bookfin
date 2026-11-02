---
id: boo-9wgg
status: in_progress
deps: [boo-u3cg, boo-7o92, boo-73yj, t3-9r9u, tb-zqvc]
links: [t3-9r9u, boo-mx5i]
created: 2026-11-01T21:37:34Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Build EPUB reading

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

**2026-11-02T13:40:10Z**

User removed HTML/Markdown support from product scope. Implement EPUB reading here; MOBI/PDF remain boo-mx5i. Historical parser research is not a production promise.

**2026-11-02T14:27:06Z**

2026-11-02 concrete navigator handoff: recommend a reviewed bounded fork of flutter_epub_viewer 2.2.1 using a separately source-pinned epub.js 0.3.93 distribution; no EPUBX production dependency is required. Both engine variants pass host contents/search/CFI probes across nine local EPUB editions; small research patches prove inline-phrase, repeated-hit, and short-document search regressions. pdfrx 2.11.0 resolves in the joint solver probe without overrides. The unmodified package deliberately FAILS two host security requirements: other hosts fall through to the WebView, and active SVG is served unchanged. Implement one passive-publication/resource-admission owner, strict navigation/permission denial, immutable processed-document identity, and existing TextPosition/bookmark wiring before accepting untrusted books. Source provenance, LGPL/native-bridge costs, API paths, exact evidence, and device acceptance gates are in docs/research/epub-navigator.md. No package approval, Android render, font application, TalkBack, or process-death resume is claimed. Standalone HTML/Markdown remain out of scope; EPUB XHTML/CSS remain required.

**2026-11-02T14:49:26Z**

Begin coordinated production implementation with prerequisite t3-9r9u in the same owner/task: first resource admission/passive publication and SVG fallback, then reader UI/records. Prerequisite remains open until review/Android acceptance; do not bypass its gate or claim production approval. Candidate selected for implementation/evaluation from reviewed research; approved behavior unchanged.

**2026-11-02T17:16:33Z**

User explicitly authorized a fresh Android EPUB acceptance attempt and screenshots after the previous host-rule stop. Test a named build with a fresh own device binding; known R1-R4 corrections continue independently. Runtime evidence must identify exact source/APK and does not certify later corrections.
**2026-11-02T16:27:45Z**

Coordinated stage 2 implementation: real Android XHTML/CSS viewport; contents and fragment navigation; local assets; search with cancellation, Unicode-offset fixes and visible incomplete errors; text size and cream/night palettes; editable bookmarks and edition-specific visible-start resume. ReaderSession is the sole state owner and guards account/source/closed-view asynchronous work. Existing personal-record persistence now serializes audio/reading merges without a second bookmark database; reading before first listening is regression-tested. Real LocalDownloads verification/admission/reopen and tamper rejection are tested. Final full app: 333 pass, 0 fail/skip; reader subset: 27 pass; corpus: 9 admissions plus 9 engine checks; engine regressions: 9 pass. Analysis clean; format 71 files unchanged; SDK/native-hook scripts pass; ARM64 debug APK and JavaScript web builds pass through Nix. Web shows an explicit unsupported reader rather than breaking the existing app. No device/browser/install/production-server work and no coverage/mutations. Host evidence does not establish Android layout, applied fonts, TalkBack, process-death resume or native interception. No ticket closure; parent owns independent review and acceptance. Evidence index: tool/evidence/reader/README.md.

**2026-11-02T16:37:13Z**

Final verification supersedes the earlier counts: 334 full app tests, 28 reader tests (included), and 14 passive-boundary tests (included), all passing with no failures/skips. Additional red-green regressions cover removed-edition loading feedback and processed-resource expansion limits. Engine checks remain 9 regressions plus 9 processed-corpus tests. Both build targets, SDK/native-hook scripts, analyzer, and formatter pass. No ticket closure or runtime acceptance.

**2026-11-02T17:33:13Z**

Fresh explicitly authorized Android attempt at d9d238b completed ordinary sign-in, actual Jellyfin12.4 ebook listing, 135959-byte download, and Read. APK source/installed SHA256 c1380e6caee8fbdb782a878c920f900463fdd74239a8dff2b8bc58f472ee2ff6 matched. Read refused before chapter rendering because real Book DTO omits Container and MediaSources. New blocker tb-zqvc. Six audited public screenshots and exact report: docs/evidence/reader/android-candidate.md. No reader, native enforcement, later R1-R4 correction, offline, or accessibility acceptance claimed. Own download removed, signed out, services/route stopped, binding released without emulator shutdown. Remains in progress.
