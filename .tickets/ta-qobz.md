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
