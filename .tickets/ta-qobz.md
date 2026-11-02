---
id: ta-qobz
status: in_progress
deps: []
links: [boo-p58t, td-4nvl]
created: 2026-11-02T00:18:50Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
---
# Provide disposable Jellyfin and Enhanced sync test environment

Provide an isolated local Jellyfin 12.4.0 installation, matching inspected upstream commit 83d0d0e7f76e23e2e085c8ff67d28b772d35967d, and Jellyfin Enhanced 12.14.0.0 for the remaining boo-p58t integration tests. Use pinned Nix inputs and a disposable data volume. Seed synthetic audiobook, multifile audio and ebook examples plus two ordinary accounts. Never restart, reconfigure or create accounts on the real server. The real supplied account is administrative, so its successful catalog/download probes cannot establish ordinary-user isolation. Resolve release source/binary provenance before treating tag 9bbf16c0de6662baeaa23e51c71505c15c560381 as the exact backend.

## Design

docs/plans/bookfin.md; docs/research/jellyfin.md

## Acceptance Criteria

Run authenticated ordinary-user catalog/range checks and negative account-isolation checks on synthetic data; expose restart controls and persistent isolated storage for boo-p58t retry/concurrency/deletion/size/retention proof. Prove which settings GET requests create storage. Provide reproducible nix develop commands without production credentials. Do not choose a new personal-record transport or run competing hardening jobs.

## Extended integration scope

Also explicitly verify multi-file ordering and ebook pairing, disabled/missing download permission and inaccessible-item behavior. Conduct existing-storage concurrency, retry, discovery, deletion and restart experiments for boo-p58t on this disposable environment; report a justified transport recommendation without silently selecting a new plugin. The live research checkout d327f68 is reference evidence only until the parent corrects its permission guard. Do not reuse that guard unchecked.

## Notes

**2026-11-02T02:02:03Z**

Implemented dedicated pinned binary-only Nix shell and disposable fixture at tool/research/sync/. Official local runtime reports Jellyfin 12.4.0 and Enhanced Active 12.14.0.0; private generated credentials, two ordinary users, loopback 127.0.0.1:7364, persistent isolated data. Production server, devices, and preview ports untouched. Runtime evidence proves ordinary-user 401/403/404 enforcement, exact Download ranges, explicit disabled/missing-permission guards without File fallback, real disc/track sorting, embedded chapters, EPUB acquisition, synthetic per-user progress, read-created Enhanced settings, real lost-ack retry duplicates, stale-snapshot lost edits/deletion resurrection, and successful clean restart of all tested state. Server is shut down; data retained. Ten research-client safety tests pass after meaningful red runs. Complete storage protocol remains unproved: app-owned private playlists provide a distinct ordinary-user isolated/discoverable primitive, so shared-snapshot failures do not prove all existing storage impossible. New t3-7fv1 tracks that protocol/retention proof or concrete rejection. Small plugin is recommended as lower-risk, not selected or installed. docs/research/jellyfin-sync.md records exact limits, hashes, failed launch attempts, and parent decision gate. Actual server DTOs are supplied for catalog integration; application mapper has not been executed here. Leave ta-qobz, boo-p58t and boo-2cgp open for parent integration and acceptance.

**2026-11-02T02:06:55Z**

Additional verification: the full repository Flutter suite passes all 34 tests through the pinned default Nix shell with --concurrency=1. The final clean restart has been rechecked after an authenticated shutdown; all persisted values and ordinary tokens survive, followed by confirmed final process exit. Earlier terminal-background/readiness mistakes and one verified disposable-process force-stop are documented separately, not presented as the clean-restart measurement. No generated credential appears in the research files or local server logs. Retained JSON evidence is about 31 KB.

## Parent review corrections

F1 resolved by narrowing claims: cross-user playlist-route GET was denied, but direct item payload GET isolation is unmeasured. Evidence includes an explicit review qualification; t3-7fv1 requires the exact-route negative check and owner control. No extra runtime measurement is claimed. F2 adds t3-7fv1 as a prerequisite of boo-p58t. Plugin lower-risk wording is now an unmeasured fallback hypothesis, not a transport decision. Environment handoff accepted as partial research; application integration remains boo-2cgp.
