---
id: t7-fyql
status: closed
deps: [boo-u3cg]
links: []
created: 2026-11-02T02:13:24Z
type: chore
priority: 3
assignee: Alexis Purslane
parent: boo-fs0n
---
# Use the pinned macOS SDK for native Dart dependency hooks

Catalog secure-storage dependencies introduce path_provider_foundation 2.6.0 and its objective_c native hook. In the current Nix shell xcrun reports that the macosx SDK cannot be found, so host Flutter tests fail before running. boo-u3cg pins path_provider_foundation 2.4.4 as a working compatibility boundary. Resolve native hook SDK discovery with project-managed pinned tools, not global Xcode selection or shell-profile changes, then remove the override.

## Acceptance Criteria

Without the path_provider_foundation override, full host app tests and Android/web builds pass through the pinned Nix shell. No global toolchain setting is changed.


## Notes

**2026-11-02T02:18:23Z**

Discovered during boo-u3cg validation. The compatibility pin keeps catalog work moving; this cleanup does not change product scope or replace boo-2cgp acceptance. Reproduce with the pinned Nix shell, without altering global Xcode or any shared Android SDK.

**2026-11-02T10:47:48Z**

Reader follow-up encountered the same host hook family: objective_c invokes xcrun with reversed argument order (--show-sdk-path --sdk macosx); fixing SDK discovery then reached Flutter native-asset codesigning. Nix sigtool refused --timestamp=none. No global SDK or signing changes were made. Research widget tests now use a Flutter-only package with no native assets; actual PDF/native verification stays in the Android APK. The research APK retains the existing root project path_provider_foundation 2.4.4 override. This does not resolve this cleanup ticket.

**2026-11-02T14:09:14Z**

Reproduced unpinned objective_c9.5.0 hook SDK failure, real sigtool timestamp failure, and reader native_toolchain_c missing-SDK error protocol. Shared pinned native-tools module now serves root/research; SDK14.4 discovery works without inherited vars, missing SDKs exit1 on stderr, sigtool source patch accepts only timestamp=none and still writes real ad-hoc signatures. Removed path_provider_foundation2.4.4 overrides in root/selected reader, locked2.6.0. Final fresh-hook root292 tests+analysis exit0; root Android/web, shared-SDK reader APK, reader host5 tests, native conversion/EPUB5 tests pass (4optional corpus skipped). OS verifies actual hook signatures; tamper regression rejects modified bytes. Nixfmt/diff checks pass. Known dependency/Wasm/font warnings remain, no runtime/device/private access or hardening. Evidence: docs/evidence/toolchain/native-hooks.md. Leave in_progress for orchestrator.

**2026-11-02T14:35:06Z**

Integrated independently reviewed native-hook correction. Parent reran SDK discovery and genuine ad-hoc signature regressions through Nix: pass, including intentional unsigned/unsupported/tampered rejection cases. Root Android/web and292 tests remain builder evidence; five successful EPUB compatibility checks are documented but their successful raw log was not retained. No runtime approval implied.
