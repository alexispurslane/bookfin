---
id: t9-ifmy
status: open
deps: []
links: []
created: 2026-11-08T16:03:51Z
type: feature
priority: 3
assignee: Alexis Purslane
parent: boo-fs0n
---
# Run the Android emulator from the x86_64 Linux dev shell

boo-2sev made x86_64-linux a build host. Its dev shell leaves out the Android emulator and system images, because the flake's only image is arm64-v8a, which an x86_64 host cannot run at usable speed. tool/bookfin emulator-create also hardcodes the arm64-v8a image. To run the app on Linux without a phone, the Linux shell needs the emulator, an x86_64 google_apis image for API 36, and an emulator-create that picks the image for the host. The emulator needs KVM. WSL2 exposes KVM only with nested virtualization turned on.

## Acceptance Criteria

On x86_64 Linux, nix develop --command bash tool/bookfin emulator-create makes an AVD that boots, and T3 device_list shows it. The aarch64-darwin shell is unchanged. docs/setup.md states the KVM requirement and the WSL2 limit.

