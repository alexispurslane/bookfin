# Bounded combined Android acceptance

Application source: `71af2886e722b7366d4d335622e55e18a151a3e0`.
Full results and limitations: `docs/evidence/reader/android-combined-20261103.md`.
This directory contains evidence, not a new application build.

Device work stopped after a failed field-entry recovery attempt.
Bookfin remains signed in and running, with five owned downloads and disabled emulator networking.
Media remains muted. Host fixture cleanup completed.
The final owned-binding release follows the evidence commit. `cleanup.json` records the pre-release audit.
Do not rerun device capture helpers under this stopped authorization.

| Files | Purpose |
| --- | --- |
| `artifact-hashes.txt`, `signatures.txt` | Exact artifact and signing identities |
| `baseline.json`, installation and reading captures | Read-only retained-action, private-file, mute, and network observations |
| `corpus.json`, `long-scan-provenance.json`, `ordinary-book-dtos.json` | Actual ordinary catalog and pinned image provenance |
| Screenshots 01–11 | OCR text, search, original access, and visible restored positions |
| Screenshots 12–20, including 18b | Actual Alice saved passage and companion conversion |
| `first-ocr-memory.json` | Sampled memory, not continuous peak memory |
| `ocr-cache-readback.json`, `ocr-accuracy.json` | Sanitized native cache output and repeatable scoring |
| `stop-audit-server.json`, `audit.json` | Exact new-account plugin comparison and original 44 preservation |
| `cleanup.json` | Host cleanup and unfinished device cleanup |
| `fixture.py` | Disposable ordinary server/catalog setup used in this lane |
| `readback.py`, `server_readback.py`, `native_readback.py`, `memory.py` | Evidence capture helpers, not private-state writers |
| `audit.py` | Host-only comparison of captured evidence |

`companion-alice-removed.json` is the removal prompt capture.
`companion-alice-files-removed.json` is the completed deletion proof.
Screenshot 18 is a loading frame. Screenshot 18b shows rendered restart text.
The item titled Empty scan actually contains recognized English text and does not prove empty-result fallback.

All recorded actions are retained synthetic acceptance actions. Account strings are replaced with SHA-256 hashes in exported action contents.
Payload hashes refer to the original stored payload bytes, before that sanitization.
Generated passwords, access tokens, private database copies, and server credentials are not included.
The owned new account has 25 retained actions, all matched by the real plugin and none pending.
The original 44 actions remain unchanged, including their 28 pending actions.

Run only the host audit to repeat the evidence comparisons:

```sh
nix develop --command python3 tool/evidence/reader/integrated/20261103/android/audit.py
```

The APK byte comparison requires the read-only artifact directory named in `audit.py`.
The audit does not establish unobserved UI behavior or recover deleted server identities.
