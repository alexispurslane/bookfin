---
id: te-d6jt
status: open
deps: []
links: []
created: 2026-11-09T22:17:13Z
type: task
priority: 3
assignee: Alexis Purslane
parent: boo-b2ey
---
# Stop the reading clock while the app is in the background

Found in boo-02sx. ReadingSpeed measures the time on a page from when the page showed until the forward turn. Time while the app is in the background counts too. A long absence falls under the slowest-speed limit and is left out, and the median leaves out a few short ones. A pause of a few minutes on many pages in a row (calls, notifications) can still lower the speed. Have the reader screen, the controller of app lifecycle events, tell ReadingSpeed when the app leaves and returns, so that a page's time leaves out the time away.

