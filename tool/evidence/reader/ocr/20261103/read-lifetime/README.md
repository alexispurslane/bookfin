# Owned OCR read lifetime correction

Base: a73b2909c76b0b67a24d62baf6cf2a012c3c546e. This corrects the next review's F1 acquisition window and F2 completion window. Earlier unsaved-selection retention remains unchanged.

The coordinator now registers one owned read operation before acquisition starts. Each admitted user joins its acquisition and leaves in a finally path. The download callback stays open until the last user leaves. Normal completion of one recognition cannot revoke a concurrent user's read. Revocation still comes from the download owner; original bytes are still verified. Close drains both recognition and admitted reads. The private read operation exposes an invariant checker through the existing coordinator checker.

## Regression evidence

`red.txt` contains two meaningful failures against unchanged production source: a selected-page revisit times out when it joins during acquisition; a selected-page revisit returns empty text when unrelated recognition fails during the revisit's original-byte verification.

The acquisition test holds the real download callback before the coordinator can publish access. The completion test holds the real file byte stream using a test-only file wrapper, then completes native recognition with an ordinary platform error. It checks the selected text, not only an emitted location or job count. Both use actual LocalDownloads and real PDF/cache I/O. Recognition itself is controlled at the platform-channel boundary.

Fixture preparation initially failed because the source was not marked as an original download and because the file wrapper lacked required methods. Those setup failures were corrected before changing production code and are not counted as regression proof. One early full-check command was interrupted after an edit script failed; the retained full log is the later completed invocation.

`focused.txt` records 21 passes across the two timing regressions and the existing coordinator/download-ownership tests. The final suite also includes a failed shared-acquisition/retry regression that checks every waiting request settles and selected text remains available after recovery.

No APK rebuild, device use, server use, publication, ticket closure, coverage or mutation work. A reviewed combined source build is required before Android acceptance. Earlier APK source 0f4084f remains superseded. Host tests do not establish Android OCR behavior or resource limits.

Final required verification: SDK/platform/native-worker checks and 480 Flutter tests pass, with three existing opt-in skips (`full.txt`). Flutter analysis reports no issues (`analysis.txt`). Formatting and git diff --check pass.
