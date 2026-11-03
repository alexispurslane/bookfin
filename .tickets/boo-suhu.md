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

docs/plans/bookfin.md. User selected fully bundled Tesseract English-fast on November 3, 2026 after the Android comparison. English is the supported OCR language; other languages remain unsupported. No first-use model download or cloud service.

## Acceptance Criteria

Demonstrate offline recognition after a fresh install on Android, reflow and search from recognized text, source-page positions, cached results, cancellable work and original-page fallback on recognition failure. Record representative scan accuracy, per-page latency, peak memory and packaged size. Document engine/model licenses and language coverage. Do not claim OCR fixes arbitrary reading order or tables.


## Notes

**2026-11-03T01:40:31Z**

Partial research-only Android measurement evidence is in tool/evidence/reader/ocr/20261102/android-device/README.md and summary.json. Verified all five APKs and source archive from 562dec2 / source 838d8a4. Baseline storage plus two actual English-fast offline reports (28 recognitions) scored with exact bundled scans/references. Fresh/repeat initialization 356.795/107.699 ms; sampled PSS maxima 269055/274751 KiB. Crop 2/31 word edits; generated English 0/37; generated French 6/40 each pass. Full pages remain unscored. Directory package+private sums 13224 KiB baseline and 28740 KiB English-fast, not complete StorageStats totals. Stopped after second bound-device wait timeout; English-best/Latin-fast/MLKit never installed. Cancellation preserved prior report; new native run and leave/reopen observed, but completed recovery not obtained, so lifecycle acceptance incomplete. Research control overlap tracked in te-bkuv. Cleanup removed both owned packages/processes, restored network to 0/1/1, retained media mute, released binding shutdown:false. Ten exact-source scorer/quality tests pass. No production OCR, PDF/MOBI/sync acceptance, license clearance, or engine/language selection. Ticket remains open/in progress; another device attempt needs explicit authorization after the stop rule.

**2026-11-03T13:23:25Z**

Renewed explicitly authorized Android attempt: tool/evidence/reader/ocr/20261103/android-renewed/README.md. Exact 838d8a4 probes/source verified; English-best, Latin-fast and bundled ML Kit each completed 14 fresh-install offline recognitions. 12 distinct completed reports/168 recognitions retained including bounded lifecycle recovery work; prior English-fast 28 recognitions unchanged and reused for comparison. Fresh initialization ms 467.225/1063.776/196.940; sampled maximum PSS KiB 281440/358416/280438. Crop word edits /31: 4/4/6; generated French /40: 6/0/4 (ML Kit two punctuation-space character deletions). English-fast/English-best/Latin-fast active Cancel and active departure preserved previous report, and reopen/new run completed. ML Kit 2.710–3.295-second runs finished before next inspected Cancel/Back, so active cancellation/stale-publication/active departure remain unproved, tracked t6-h28u. One old-reference refusal followed exact advice once; fresh snapshot/retry succeeded. No timeout or engine failure. Ten pinned scorer/quality tests plus raw/scored identity and preservation validation pass. Owned probes/processes removed, original network 0/1/1 restored, media remained muted; no normal-app changes or production engine/terms/language decision. Ticket stays in progress.

## User selection — November 3, 2026

Use the measured Tesseract English-fast candidate for production integration:
Tesseract4Android 4.9.0 / Tesseract 5.5.1 with the pinned English-fast model
from probe source 838d8a4. Preserve exact model/source/license provenance.
Do not add English-best, Latin-fast, ML Kit or language downloads. This choice
approves implementation, not production runtime or distribution compliance.
The shared PDF reader owns page positions, reflow/search and original access;
recognition supplies cached page text. Follow existing source identity and
download ownership for cache lifetime and cancellation. Normal Android format
acceptance runs separately and remains a prerequisite to overall closure.

**2026-11-03T14:37:57Z**

Production-source milestone: bundled English-fast now supplies the existing PDF text/reflow/search path. Account/source-owned OCR cache uses existing download read/removal ordering and revocation. Original-page fallback, explicit unreliable-text retry, cancellation with native drain, retry during drain, and close-failure PDF cleanup have behavior tests. Parent 44d53af admission correction integrated as 78ce699 with both byte detection and OCR wiring. Evidence: tool/evidence/reader/ocr/20261103/production; implementation and terms gates: docs/ocr-implementation.md. Final project checks and clean-source APK/source handoff follow. No Android OCR acceptance, distribution approval, coverage/mutation campaign or ticket closure.

**2026-11-03T14:38:41Z**

Final pre-build checks pass: 453 full Flutter tests with three existing opt-in skips; Android SDK/native hook checks and production Java worker test pass; Flutter analysis reports no issues. Meaningful red evidence covers actual PDF text supply, ownership revocation, native admission, explicit unreliable-text retry, retry during cancellation drain and close-failure native-owner cleanup. Next is the normal ARM64 app build and exact-source export, with no installation.

**2026-11-03T14:46:15Z**

The first committed-source APK attempt stopped at Gradle script compilation before packaging. Its java extension shadowed the java.security package. Explicit File and MessageDigest imports fix the namespace collision; this is a build-script correction, not a behavior-red claim. The failed log is preserved. Direct Gradle compile attempts cannot load the Nix included Flutter build; use the normal Flutter wrapper for final compilation/package verification. No APK from the failed source was handed off.

**2026-11-03T14:52:31Z**

Normal app compilation succeeds after the import correction, including Android Java/Kotlin and native libraries. Exact package verification meaningfully rejects the candidate because Flutter default ABI filters include dependency libraries for unrequested architectures despite --target-platform android-arm64. Gradle now derives dependency ABI filters from the requested Flutter targets (and leaves split-APK filtering to Flutter), rather than hard-coding a product-wide ARM64-only restriction. Package-architecture-red.txt records the observed incompatible native entries. Rebuild and verification follow from a new clean source commit.

**2026-11-03T14:57:11Z**

Verified clean-source normal-app ARM64 debug APK and matching source: code source 5fca4a23843c57d4ba162d94500e700bd036266f; APK .cache/artifacts/ocr-20261103-production/bookfin-5fca4a2-arm64-debug.apk, 131217891 bytes, SHA-256 5b0f6d3d451bfb36671e8fc19084f2084064e21d4edc26fdbf8d982308a0bf32; source directory source-5fca4a2, Bookfin tar SHA-256 d24275341d56639f881081b3832422d8e13725678b9c53744df68ec16a388404. Exact AAR/model/notices, all 13 ARM64 native libraries, 16 KiB ELF/package alignment, APK v2 signature, permissions, normal package/entrypoint and clean source stamp pass. Final-source rerun: 453 tests pass, three existing opt-in skips, SDK/native hook/production Java worker checks pass, analysis clean. Evidence/provenance/source manifest are in tool/evidence/reader/ocr/20261103/production. Only this checkout Gradle daemon stopped; no owned Gradle/Kotlin process remains. No install/device/server/PR/publish/coverage/mutation work or ticket closure. Normal-app Android OCR acceptance, layout/resource measurements and distribution/source/installation-information decisions remain.

**2026-11-03T15:55:24Z**

Review corrections F1-F4 on preserved acd2333 builder checkout: retain every pinned textual hOCR line class and reject nested words; keep selected recognition for search/revisit and cache-save failure; document-owned text representation coordinates retain unresolved page-two resume/bookmark addresses through real SQLite close/reopen, cache loss/corruption, failure and cancellation; settle native Error and close futures, reject unsafe reuse, preserve IOException retry and global permit cleanup. Preserved 78ce699 format admission unchanged. Exact source hashes and red/green logs: tool/evidence/reader/ocr/20261103/review-corrections. Final focused 53 pass; full 474 pass, three opt-in skips; analysis clean; SDK/native-worker and actual host English model checks pass. No Android OCR acceptance, live services, coverage/mutation campaign, distribution approval or ticket closure. Corrected clean-source APK packaging follows as separate evidence.

**2026-11-03T16:07:35Z**

Corrected APK/source handoff: clean source 0f4084f7c670a1b6866f9543ac7af9f1949ba8a3. Normal ARM64 debug APK 170179115 bytes, SHA-256 8be5a98d9201436fd2d6e7499f48f658471e3ed1ac6f777f5b6404e024f13cea. Exact Git source tar SHA-256 ee44e6050136f1395f25baeacbfcfaeb6148ab6070c98eacfd468fdc3fddce47. HANDOFF.md and provenance.json under tool/evidence/reader/ocr/20261103/review-corrections bind source/model/licenses/build/verification. Both normal Flutter builds succeed. Thirteen ARM64 libraries, four exact AAR libraries, English model, 29 reader and seven OCR notices, 16 KiB ELF/package alignment, unchanged six permissions and v2 debug signature verified. Post-build required checks on the clean source commit: 474 pass, three opt-in skips, clean analysis. Extra direct standalone Gradle compile invocation fails during settings initialization and is recorded as a limitation, not a passing check; supported Flutter builds pass. Owned Gradle daemons stopped; final status empty and no owned compiler remains. The containing evidence commit is not the APK source. Parent review/integration, Android OCR acceptance/resource/layout tests and existing native-reader distribution/replacement/source-delivery gates remain open. No ticket closure or publication.


2026-11-03 parent correction of second review R1/R2: retain unsaved selections until document close; separate verified text reuse from bounded native admission, including reuse of an active download read during cancellation drain. Added seventeen-page cache-publication failure and held-recognition regressions, plus real download-queue reuse/removal proof. Two meaningful reds; final required scripts and 477 Flutter tests pass, three opt-in skips, analysis clean. Evidence: tool/evidence/reader/ocr/20261103/selection-lifetime/. No refreshed APK or Android acceptance. Source re-review and integration remain pending.
