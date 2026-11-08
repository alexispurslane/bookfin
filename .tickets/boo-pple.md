---
id: boo-pple
status: closed
deps: []
links: []
created: 2026-11-07T18:34:08Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Read series from titles with text after the (Series #N) part

Found on the Pixel 8 on 2026-11-07. '2.6 Sun Eater Series - Queen Amid Ashes (The Sun Eater #4.5) by Christopher Ruocchio' is not grouped into The Sun Eater, because the series pattern only matches a title that ends with the parenthesis. Also strip the leading '2.6 Sun Eater Series - ' and trailing ' by Author' noise if a safe rule exists.


## Notes

2026-11-07: Checked against the Pixel's saved library of 1,478 items. Six titles change, and the count of series with two or more books stays at 134:

- "2.6 Sun Eater Series - Queen Amid Ashes (The Sun Eater #4.5) by Christopher Ruocchio" becomes "Queen Amid Ashes", Sun Eater 4.5. Before, it took its item number 2 and sat after Howling Dark.
- "Sun Eater Series - Kingdoms of Death-Christopher Ruocchio" becomes "Kingdoms of Death".
- "Stephen Baxter - (Destiny's Children #1) Coalescent" and its #2 lose the author lead.
- "Peter Watts - Maelstrom Rifters Trilogy, Book 2 (Rifters Trilogy Series #2)" becomes "Maelstrom Rifters Trilogy, Book 2". The trailing series words stay, because no safe rule removes them.
- "The Unreal and the Real Vol1 Ursula K Le Guin - Where on Earth (...)" becomes "Where on Earth".

"The Lesser Devil" shows Book 1 because its Jellyfin name is "The Lesser Devil (Sun Eater #1)" and its item number is also 1. The server metadata is wrong, and Bookfin cannot detect it. The user can set its position with a catalog correction on the book page.
