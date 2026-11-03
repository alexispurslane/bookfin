# Resumed Android acceptance, November 3, 2026

The authorized test lane ran from main `e4baaf9` on the retained Android emulator.
It installed the exact normal APK from clean source `d8e1021`, SHA-256
`8b31c7448f746226453d4677f944c9ba4f5668f657bba8015f94973372744e09`,
in place. No rebuild, reset, uninstall, private-row edit, or production change occurred.

Full evidence, exact limits, errors, screenshots, readback, and audit are in
`tool/evidence/reader/integrated/20261103/resumed/README.md`.

| Scope | Result |
| --- | --- |
| `t0-ys9g` cancellation/rendering | Accepted: three active cancellations kept reader controls and originals usable; reliable retry supplied English reflow; active departure returned to details |
| Native drain and exact late-callback boundary | Unverified: active UI is not a native trace; one cache appeared during the Back command, before the first completed-departure capture |
| Genuine blank fallback | Passed for both a dense book's blank second page and the separate blank original |
| Nonzero resume/bookmark | Character 574 and source page 2 survived the relevant fallback/reopen paths; a stored character-574 bookmark was invoked during the uncached cancellation sequence |
| Cache lifetime/source ownership | Cached reopen kept exact cache metadata; ordinary removal removed that edition's original/cache and preserved the other originals |
| `t0-yy48` offline route and explicit sync | Passed: route absent during action creation; five new actions were pending locally and absent remotely; explicit Sync now preceded the periodic interval and acknowledged them exactly |
| Unicode readback | Exact curly quotes, accents, Chinese, emoji, positions, identities, payload hashes, replica/sequence, and causal contexts matched the real unchanged plugin |
| Original 70 retained actions | All unchanged, including all original 28 pending flags; no original-account recovery claim |
| Later new actions | Four acknowledged by background sync during ordinary redownload, not attributed to the earlier button; all nine new-account actions matched final plugin readback and none remained pending |
| New minor defect | `t8-oitu`: a PDF with no available local original also showed an EPUB-specific unopened-reader message |
| Cleanup | Complete: ordinary removal, sign-out, app close, network `0/1/1`, media muted, owned server/routes/private data removed, read-only final audit, T3 release with `shutdown:false` |

The repeatable evidence audit passed. Final device state retained 79 actions and
28 pending actions, with SQLite integrity `ok`. No original, cache, or new pending
action recovery path was deleted improperly. The bundled private English model
and large system text size remained.

`t2-00a4` still needs authentic recovery of the original account. `boo-suhu` still
needs fresh-install offline recognition on a separate supported target, native
callback-boundary proof, and runtime cross-account ownership checks. Only the
retained emulator was exposed by T3 discovery. Physical-phone, two-device, real
TalkBack, and legal work remain separate. No tickets were closed; parent owns
integration and closure. Existing serif-font defect `te-rtok` remains unchanged.
