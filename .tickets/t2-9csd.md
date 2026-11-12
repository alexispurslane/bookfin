---
id: t2-9csd
status: open
deps: []
links: []
created: 2026-11-11T22:44:26Z
type: task
priority: 3
assignee: Alexis Purslane
parent: boo-z3is
---
# Find speech landings in PDF editions

Speech search (boo-vh77) reads the words of EPUB and MOBI editions only. A PDF needs its words with visible characters from PDFium's text layer, as pdfOutlineOf counts them, in the PDFium worker. No PDF in the user's library has an audio counterpart (t3-a4fi), so this waits.

