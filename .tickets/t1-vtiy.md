---
id: t1-vtiy
status: closed
deps: [t9-4jqk]
links: []
created: 2026-11-07T22:33:51Z
type: bug
priority: 2
assignee: Alexis Purslane
parent: boo-bquq
tags: [engine-rules]
---
# Downloads finds a downloaded file during a rebind that changes the book list

Found during boo-petv on 2026-11-07. Downloads.localFile (lib/downloads/local_downloads.dart) captures _generation, awaits _binding, and returns null when a bind with a different book list ran in between. Downloads.bind starts a new generation whenever its source signature changes, for example when a failed library refresh keeps only downloaded books.

Effect: Playback asks for the local files of the saved book while it reopens at launch. If that rebind lands during the lookup, Playback gets null for a file that is on disk. It shows 'Download every file in this audio edition before listening.' and drops the reopen. The book reopens only after Playback is bound again. A listener tap on play in the same window fails the same way.

Rules: engine rule 2 (cached information is fully usable).

Target: a lookup answers for the binding that is current when it completes. If the source is still bound under the same account, wait for the new binding and look it up again. Return null only when the source is no longer bound or its file is missing or corrupt.

Owned files: lib/downloads/local_downloads.dart and its tests. Order: after t9-4jqk, which owns the same file.

## Acceptance Criteria

With a downloaded edition, a localFile lookup that overlaps a Downloads.bind with a smaller book list that still holds the edition returns the file URI. A lookup that overlaps a bind without the edition, or with another account, returns null.


## Notes

**2026-11-07T22:35:52Z**

Handed to the running t9-4jqk agent, which owns lib/downloads/local_downloads.dart; it lands with t9-4jqk's branch.
