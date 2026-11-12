---
id: boo-68pb
status: closed
deps: []
links: []
created: 2026-11-12T13:54:30Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-z3is
---
# Hear speech windows only for audiobooks whose book has an ebook

User request 2026-11-12: "make sure that the speech-to-text stuff is never done to an audiobook that does not have an e-book corresponding ... so that we don't sap battery unnecessarily." HearingPolicy checks that the audio edition's book also has a text edition before listening windows, record windows and the fill. Speech at the tap starts only from an ebook's History, so it needs no check.

