---
id: t7-fyql
status: in_progress
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
