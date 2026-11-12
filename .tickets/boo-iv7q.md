---
id: boo-iv7q
status: open
deps: []
links: []
created: 2026-11-12T03:24:46Z
type: task
priority: 3
assignee: Alexis Purslane
parent: boo-fs0n
---
# Show the kept last page for books that embed their own fonts

boo-sy2d keeps no last-page picture for a book that uses its own fonts, so such a book still shows about 35 ms of blank paper on reopen. Option: key the kept page on the font files and load them before the first frame. Cost: font loading moves onto the reopen path and the key gains inputs. First measure how many books in the user's library embed fonts.

