---
id: boo-n1cn
status: open
deps: []
links: []
created: 2026-11-08T12:48:01Z
type: bug
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
---
# Finish and save every started OCR page when the reader leaves it

User request (2026-11-08): OCR and reflow must continue in the background when the user turns away from the page or leaves the PDF. Today cancel() in lib/reader/ocr.dart only bumps _generation and sets recognizing false; nothing stops the native Tesseract worker, which finishes the page, and ocr.dart then drops the result without writing the disk cache (.bookfin-ocr). This happens on a page turn (pdf_viewport.dart _load calls onCancelRecognition), on Cancel, and when ReaderSession._clear closes the book (session.dart:355-358). The on-screen message already promises that the page can finish in the background. Required: every recognition that starts finishes and is written to the disk cache, whatever the reader does next: turning pages, Cancel, closing the book, opening another book, or the app going to the background while the process lives. Cancel only stops the reader from waiting. Requests for pages that have not started yet can be dropped. Also look at the limit of two pending requests ('Recognition is busy') when the user turns pages quickly. Tests must cover each of these exits.

