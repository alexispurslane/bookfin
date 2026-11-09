---
id: boo-1u66
status: closed
deps: [t7-bbv1]
links: []
created: 2026-11-09T19:31:05Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-b2ey
---
# Keep a book's main text size so the first page never waits to measure it

Found in the boo-0ari merge. With the text size override on, the first page of a book waits for measureMainTextSize, which styles the three longest sections in a worker: 8 ms median and up to 522 ms (Roget's Thesaurus) on the host, and probably 1.5 to 2.5 times that on a phone. That is on the path to the first page, which t7-rcyp just made fast. Keep the measured main text size with the kept admitted book (lib/reader/admitted_books.dart) or with the page map (t5-4lbx), keyed by everything that it depends on (media queries make it depend on the page width and height), so that only the first open of a book at a page size measures it. Decide whether media queries must count at all for this measurement.


## Implementation notes (2026-11-09)

- Media queries do not count. Of the 90 corpus books, 8 have media queries on the page width (Standard Ebooks plays and Ulysses: `max-width: 400px` and `600px`), and none of them sets a type size or hides text. So `measureMainTextSize` measures on one page, 412 × 671 pixels, and a book has one main text size.
- Admission measures it and the admitted book keeps it: `Publication.mainTextSize`, in the record's header. `Publication.revision` is now 2, so each kept book admits once more and gets its size. The page source reads the kept size and no longer measures, so no page waits for the measurement.
- The record write stays atomic (AdmittedBooks). A record whose size is not finite and above 0 is unreadable: it is set aside and the book admits and measures again. A changed file has another digest, so it admits and measures again.
- Cost: the first open of a book, which admits it, now also measures its main text, also for a reader who never used the size buttons. On the host that was 8 ms median and 522 ms at most (Roget's Thesaurus).
- The cascade is now part of admission's output. A cascade change that changes a book's main text size must raise `Publication.revision`. Follow-up: td-hyny.
