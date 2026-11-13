---
id: boo-721h
status: open
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

