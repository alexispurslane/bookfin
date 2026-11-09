---
id: boo-j1lm
status: open
deps: []
links: []
created: 2026-11-09T15:08:24Z
type: feature
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
---
# Show every Jellyfin book library by default, and let the user hide some

Found 2026-11-09: the user's Ebooks library (CollectionType books, 24 PDF and EPUB items) never appeared, because Bookfin reads only the libraries ticked in Settings > Libraries, nothing is ticked at sign-in until the user chooses, and a library added later stays unticked with no hint. The server and the catalog parser are fine (checked against the real server: catalogEntries and buildBooks read all 24).

Decision (user, 2026-11-09): show all, hide some. Every book library on the server shows by default, including ones added later. The user unticks a library to hide it.

Model: the stored state becomes the set of hidden library ids, not the set of shown ones; the shown libraries are the server's book libraries minus the hidden ones, computed at each refresh. Sign-in needs no library choice step (remove it, or keep it only as an optional hide step if the approved mockup requires the screen). Migration of saved catalogs: start with nothing hidden, because old selections were made under the old rule (this is what brings the user's Ebooks back). A library that disappears from the server drops out of the hidden set. The Settings row reads e.g. 'Audiobooks, Ebooks · 2 of 2 shown'. Keep the cache-first start: the saved catalog shows at once and the refresh backfills the new library silently.

