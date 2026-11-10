# Word geometry of scanned pages from the layout pass

Date: 2026-11-10. Ticket: tb-jidt. Epic: boo-fval. Design: `docs/plans/pdf-word-image-reflow.md`, sections "Word geometry", "The layout pass" and "Text attachment".

This folder is evidence. It is not product code.

| File | What it shows |
| --- | --- |
| `red.txt` | Before the implementation: the new host tests fail on behavior, against stubs with the final interface. Geometry is empty, no layout pass runs, no record is saved, and the queue runs the shown page's work last. The test of the unchanged digest passes, because it guards text that must not change. |
| `device.txt` | After the implementation: all 8 device tests pass on the AVD `bookfin-tb-jidt` (android-36 google_apis arm64-v8a, debug build). |

On the emulator, through `PdfBook.geometry` and `PdfBook.attachedText` (one run, debug build):

| Page | Layout words | Words shown after | Text attached after |
| --- | --- | --- | --- |
| scanned | 36 | 172 ms | 337 ms |
| skewed | 42 | 268 ms | 405 ms |

Both pages gave the reading text digest of recognition alone, so places saved before this ticket still resolve.
