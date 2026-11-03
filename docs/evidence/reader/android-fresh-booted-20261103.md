# Fresh-install offline OCR and durable upload acceptance, November 3, 2026

This lane continued from `b186860` after `td-e1sx` resolved the disposable AVD's pinned image path.
It installed the exact normal APK from clean source `d8e1021` on `local/emulator-5556` after proving the app absent.
No production edit, rebuild, child, hardening, publication, or ticket closure occurred.

Full evidence, audit, errors, hashes, and cleanup are in
`tool/evidence/reader/integrated/20261103/fresh-booted/README.md`.

| Check | Result |
| --- | --- |
| Fresh first offline OCR | Passed; no earlier private model/cache, radios off and owned USB route removed, bundled English recognition completed |
| Reader | Passed reflow, search, original access, stored character-611 bookmark/place, cache reuse, and genuine blank fallback |
| Durable pending | Five exact reading/Unicode-bookmark actions survived disconnected close/relaunch with unchanged identities, payloads, and pending flags |
| Explicit sync | Eight ordinary offline Alice actions acknowledged after explicit Sync now completed 11.953 seconds after launch-command start, before the 30-second periodic interval |
| Exact plugin readback | All identities, payload hashes, values, replica sequence, and causal contexts matched unchanged Storage 0.1.1.0 on real Jellyfin 12.4.0 |
| Repeat/restart | Repeated sync added no duplicate object; acknowledged records stayed stable after restart |
| Account ownership | Bob could not use Alice's original/cache/bookmark; his own download/OCR created a separate cache, and removing it preserved Alice's cache |
| Final records | Ten acknowledged actions retained: nine Alice and one Bob; zero pending, SQLite integrity `ok` |
| Cleanup | Ordinary download removal/sign-out/close; network `0/1/1`, media muted, route/service/private copies removed, owned AVD released and shut down |

The original `local/emulator-5554` was never opened or operated.
Its earlier 79 actions/28 pending were not freshly measured; authentic original-account recovery remains separately blocked.
No identity rewriting, broad backup search, or claim that fresh-account success recovers those records occurred.

Lost acknowledgment and exact native callback ordering remain unverified. Existing `t8-oitu` reproduced; no new production defect was found.
UI coherence `boo-4ixi`, broader hardening, legal/release approval, and the physical-phone trial remain separate.

The handoff APK is
`/Users/alexispurslane/.t3/worktrees/bookfin/t3-f29350e1/.cache/artifacts/bookfin-d8e1021-cancel/bookfin-d8e1021-arm64-debug.apk`.
Its SHA-256, also matched by the installed package, is
`8b31c7448f746226453d4677f944c9ba4f5668f657bba8015f94973372744e09`.
The source archive is the adjacent `source/bookfin-source.tar`, SHA-256
`3dd0c18fb2cdc3b94e8831f12b4ef92d573bccd73392a626b3c46de1dae45f60`.
These are verified debug artifacts for the parent's phone trial, not release approval.
