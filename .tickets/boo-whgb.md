---
id: boo-whgb
status: open
deps: [boo-77sj]
links: []
created: 2026-11-08T17:39:24Z
type: feature
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Run CI on Tangled on every push

User request (2026-11-08): Tangled CI (spindle) workflows in .tangled/workflows/ that, on push to main and on pull requests: check format and analyze, run flutter test, build the flake packages (APK, Linux app), and run the Linux desktop acceptance test under a virtual display; Android emulator acceptance only if the runner offers KVM in the guest. Facts from the docs (2026-11-08): engines microvm (nixos, x86_64 default) and nixery; no macOS runners; hosted spindle timeout 5 minutes including queue; self-hosted spindle needs Linux with KVM and a public HTTPS hostname. The runner (hosted, or self-hosted on the user's Linux machine) is still the user's open decision; do not set up a spindle until the user chooses.

