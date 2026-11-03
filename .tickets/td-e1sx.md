---
id: td-e1sx
status: closed
deps: []
links: []
created: 2026-11-03T21:33:14Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
---
# Make the disposable Android acceptance AVD resolve the pinned Nix image through T3

Fresh acceptance lane from 2d11125 created bookfin-accept-20261103-db111f95 with project-managed avdmanager and pinned API36 google_apis arm64-v8a image. T3 device_list discovers it, but device_open exits code1 before online and returns no bound command. Host invokes /Users/alexispurslane/Library/Android/sdk/emulator/emulator; new config uses relative system-images/android-36/google_apis/arm64-v8a/ absent under that host SDK. Image exists at /nix/store/in52zy1w2yv0197h7553n827h8f03x8k-bookfin-android-sdk/system-images/android-36/google_apis/arm64-v8a/. Native stderr was not supplied, so sole boot cause is not confirmed. Post-failure investigation stayed read-only, as directed. Do not manually boot, replace host SDK, touch retained AVD, or evade T3 binding.

## Acceptance Criteria

Resolve the newly owned AVD pinned image through supported provisioning or supported T3 host configuration, then device_open returns a usable bound command. Preserve retained emulator and all original79 actions/original28 pending. Continue fresh-install offline OCR and durable Unicode pending acceptance separately; do not infer those passes from discovery.

## Notes

**2026-11-03T21:39:10Z**

Parent recovery: changed only owned bookfin-accept-20261103-db111f95 AVD image.sysdir.1 from relative system-images/android-36/google_apis/arm64-v8a/ to verified absolute /nix/store/in52zy1w2yv0197h7553n827h8f03x8k-bookfin-android-sdk/system-images/android-36/google_apis/arm64-v8a/. Backed up config.ini.before-image-path. T3 device_open succeeded on one retry, returned local/emulator-5556 and bound command. No manual boot, application install, UI or settings actions. Released parent binding shutdown:false for exclusive acceptance continuation. Retained emulator5554 untouched. Provisioning blocker resolved; fresh-install/pending acceptance still required.
