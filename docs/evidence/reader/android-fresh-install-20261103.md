# Fresh-install Android attempt, November 3, 2026

The focused test lane from parent `2d11125` created a separate disposable AVD
with project-managed Nix tools. T3 discovered it as
`local/bookfin-accept-20261103-db111f95`, but boot failed with exit code 1 before
online. No bound `agent-device` command was returned. The suggested manual boot
was not run because it violates the Device-panel-only rule.

Read-only investigation found a relative image path in the new AVD that is
absent under the host SDK used by T3. The pinned project SDK contains that
image. Native stderr was not supplied, so the sole failure cause is not proved.
The setup follow-up is `td-e1sx`. The new AVD remains registered and unbooted.

Fresh-install offline OCR and durable Unicode pending-upload acceptance are
blocked before installation and account creation, not passed or failed runtime
checks. The required APK, source archive, and unchanged plugin hashes match.
No production change, rebuild, device input, fixture, route, or new personal
action occurred. No physical phone was accessed.

The retained `local/emulator-5554` was not opened or operated. Its previous
79 actions and 28 pending actions were not newly measured. Original-account
recovery remains separately blocked; new-account success would not recover it.
No ticket closure, broader hardening, or overall release approval is implied.

The full report, exact error, hashes, scoped audit, paths, and cleanup are in
`tool/evidence/reader/integrated/20261103/fresh-install/README.md`.
