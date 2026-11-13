---
id: tb-v0oz
status: closed
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

## Parent repair and verification — 2026-11-13

Updated both callers directly on main after gallery integration at `96645868`.
The raster fixture writes downloaded PDF bytes to a temporary file, keeps it
through rendering and document disposal, then removes the directory even if
opening/rendering/disposal fails. The geometry fixture already owns a file and
now passes its path, preserving the existing lifetime and cleanup. No production
behavior changed and no extra test of test setup was introduced.

Before the repair, `nix develop --command flutter analyze --no-pub
integration_test/ocr_layout_test.dart` exited 1 with exactly the two reported
argument-type errors. Log: `/tmp/tb-v0oz-analysis-red.log`. This is static
compatibility evidence, not a behavioral red test or device execution.

After the repair, the integrated driver ran `nix develop --command bash -c`
with changed-file `dart format --output=none --set-exit-if-changed` followed by
`flutter analyze --no-pub lib test integration_test`. Formatting checked 11
files with zero changes; all three analysis roots passed with no issues.
Logs: `/tmp/boo-0740-integrated-format.log` and
`/tmp/boo-0740-integrated-analysis.log`.

Device execution remains unverified under `t1-dth0`; the Device panel was not
retried or bypassed. This ticket repairs the compile-time API mismatch only.
No coverage, mutations, deployment or additional reviewer was needed.
