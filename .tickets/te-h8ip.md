---
id: te-h8ip
status: in_progress
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

**2026-11-10T12:58:50Z**

Built on 2026-11-10 as the user decided: in reflow, a page whose own content cannot reflow (absent or unreliable) shows its original page fitted to the screen with no message. PdfTextStatus gained 'failed' for reader failures (recognition failure, fatal recognition, removed download, no downloaded book, canceled wait). Only a failed text carries a reason, and only failures, a text read error and an unmatched saved place keep their quiet line. Saved places, cache keys and digests are unchanged. The search note that counts skipped pages is unchanged.
