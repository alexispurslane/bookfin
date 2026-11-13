---
id: tb-v0oz
status: open
deps: []
links: []
created: 2026-11-13T14:00:23Z
type: bug
priority: 3
assignee: Alexis Purslane
parent: boo-fs0n
---
# Update OCR device tests to open PDF files by path

Found during boo-0740 on 2026-11-13. nix develop --command flutter analyze lib test integration_test reports argument_type_not_assignable in integration_test/ocr_layout_test.dart:81 and :448: PdfRuntime.instance.open receives Uint8List, but its first argument is now String (a file path). Both calls are present unchanged at a85c8789e9a14c4d978f94e64db3c6cacfafd8a0. Update these device-test callers to the file-path API, retain their PDF lifetime and cleanup, and run affected analysis. Device execution remains subject to t1-dth0. Log: /tmp/bookfin-boo-0740/analysis.log.
