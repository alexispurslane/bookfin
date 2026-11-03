# Sync review corrections

Source boundary: after reader milestone `94457bf`, before the correction commit
that contains this evidence. The original `ccff7dc` APK is not this candidate.
Tests ran on November 2, 2026 in America/New_York; some UTC timestamps fall on
November 3. Existing evidence is unchanged.

| Evidence | Meaning |
| --- | --- |
| owner-choice-red.txt | Meaningful rejected-refresh races in audio and reading, both coordinator/player resume choices, and a stale displayed choice fail before fixes. |
| journal-screen-red.txt | Malformed persisted journal shapes/references fail with raw errors; conflict descriptions expose identifiers before fixes. |
| pending-account-red.txt | Restoring an unpersisted audio snapshot must not mark its unsaved bookmarks as already observed by the store. |
| focused-green.txt | 193 focused sync, playback, and reader tests pass; the optional real-plugin test is skipped without its private fixture configuration. |
| full-host-initial-analysis-info.txt | SDK link/platform/native-tool checks and all 397 Flutter tests pass; one optional real-plugin test skipped. The following analyzer run found one missing-braces style information, subsequently fixed. |
| analysis-green.txt | Final `flutter analyze` passes with no issues after adding the braces. |
| actual-plugin-green.txt | C# plugin build has no warnings/errors; two durable ordinary-account SQLite clients pass authenticated real Jellyfin/plugin integration. The disposable server is stopped by the runner. |

All commands use the pinned Nix shells. The iOS SDK messages come from native
dependency hooks on a host without an iOS SDK; this evidence makes no iOS claim.
No acceptance devices or ports 7364/7365 are used. Controlled HTTP fixtures bind
loopback port zero; the real plugin runner checks and owns ports 7464/7465.

No save-latency, lifetime-journal-size, Android runtime, power-loss, disk-full,
plugin deployment/upgrade, or app-complete claim follows from these tests.
`t6-t9po` and `t6-il6y` remain release gates. Parent owns review, integration,
acceptance, coverage, mutation testing, and ticket closure.
