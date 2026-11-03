# Selected OCR text lifetime corrections

Parent correction from de57e6713449f3c8c9635499bb2241010a409ada addresses review R1/R2. The OCR stack is not integrated into main yet.

Unsaved successful selections remain in the document until close. The sixteen-page memory eviction rule applies only to disk-backed selections. Memory can grow with unsaved results; no production Android memory bound is claimed.

Text reuse happens before admission to the native recognition queue. It verifies original bytes and current download ownership. While native work holds the download command queue, reuse borrows that existing read interval; cancellation changes recognition generation but does not end download ownership. Removal/account/source revocation still rejects reuse. The active interval is cleared in finally. Native recognition remains serialized and limited to one active and one waiting operation.

## Evidence

- red.txt: two meaningful failures against unchanged production source: seventeen-page failed-cache case loses text; selected-page revisit waits behind unrelated recognition and times out.
- green.txt: fourteen coordinator tests pass after the first correction.
- focused.txt: thirty-two coordinator, storage-position and download ownership tests pass, including cancellation drain.
- ownership.txt: five tests pass after adding a real LocalDownloads command-queue reuse/removal regression. An initial invocation was interrupted before test execution and rerun; the retained log is the completed run.
- full.txt: required SDK/platform/native-worker scripts and 477 Flutter tests pass, with three existing opt-in skips.
- analysis.txt: no issues. Formatting and git diff --check pass.

Native recognition is controlled at the platform-channel boundary in the new tests; real PDF rendering, cache I/O and download ownership execute. Full suite includes the existing actual host-model test. None establishes Android JNI or normal-app OCR acceptance.

No APK was rebuilt for this correction. Earlier APK source 0f4084f is superseded for OCR acceptance. Build the reviewed integrated source before device acceptance. No device, server, publication, ticket closure or coverage/mutation work occurred.
