---
id: te-h8ip
status: open
deps: []
links: [boo-pw1d]
created: 2026-11-10T02:44:18Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Decide whether recognized cover and title pages of a few short lines can reflow

decodeRecognizedPage marks a recognized page unreliable when it has at least 4 lines and 80% or more of them hold two words or fewer. A book cover or title page (Nihil Unbound source page 1: 'palgrave', 'macmillan', 'Nihil Unbound', 'Enlightenment and Extinction', 'Ray Brassier') is a few short lines in reading order, so reflow says 'The text of this page cannot be put in reading order.' on it. The same rule in _textWarning (pdf.dart) treats extracted text layers alike. The rule exists to refuse scattered labels such as diagrams and tables. A change trades covers that reflow against diagrams that reflow as a jumble, so it is a product decision. Found during boo-pw1d.


## Notes

**2026-11-10T12:50:56Z**

User decision (2026-11-10): a page whose own content cannot reflow (cover, contents, diagram, table, no text) shows the original page fitted to the screen, with no message. Machinery failures keep their quiet line.
