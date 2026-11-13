---
id: boo-721h
status: in_progress
deps: []
links: []
created: 2026-11-12T23:41:00Z
type: bug
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Keep downloaded books, playback and the reader usable after a 401

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: path confirmed, trigger plausible. lib/catalog/transport_io.dart:81-83, lib/catalog/controller.dart:728-735, lib/app/account_binding.dart:91-97. Any 401 during a background refresh clears the session and the library, deletes the saved token, binds Playback and the reader to no account (which stops audio and closes the book), and pops every route to the sign-in form. A revoked token or a sign-in proxy with an expired cookie triggers it. Engine rule 2 says that cached information is fully usable. Separate the local account (identity, saved library, downloads, records) from the state of the server credential. A 401 marks the credential as "needs sign-in" and stops only the work that needs the server. Delete the token only on an explicit sign-out or when a new sign-in replaces it.

## Astra implementation scope

Use the settled distinction between the local account and whether its server credential can be used. A background 401 must preserve the local account, cached books, downloaded files, active local playback, the open reader and durable personal records. Keep local saves and pending sync actions working. Mark that sign-in is needed and suspend work that requires the rejected credential. Retain the saved token until explicit sign-out or successful replacement; a failed or cancelled sign-in must not implicitly erase the local account. Successful sign-in to the same account resumes server work without losing the current book or saved place. A different account and explicit sign-out retain account isolation.

Provide a usable sign-in-again action through the existing account UI and reuse its form and glass components. Preserve existing visual structure and narrow subscriptions. A 403 that explicitly denies library access remains a distinct condition; this ticket does not grant access that the server has denied. Preserve the one-hour resume freshness rule, cache-first launch, and integrated record-upload scheduling. The concurrently running boo-7z9a owns separation of catalog choices from its cache; do not duplicate that migration. The parent resolves integration overlap.

Required meaningful red-green evidence covers a background 401 during active local playback and reading, subsequent local saves, restart from the retained account, no automatic server work with the rejected credential, failed/cancelled/successful reauthentication, explicit sign-out, a changed account, and obsolete request completion. Exercise real controllers and bindings as well as the sign-in UI. Update tests that require automatic sign-out after 401. Run catalog, app, downloads, playback, reader persistence and sync checks, affected analysis/format, and the full Flutter suite at concurrency two through Nix, one heavy command at a time.

Implementation and direct fixes use codex/gpt-6-astra with reasoningEffort xhigh. Exactly one fresh read-only reviewer uses the same model at high. Parent owns integration, acceptance, hardening and closure. No device work, coverage, mutations, push, PR or live deployment.
