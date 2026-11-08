---
id: tf-bb2j
status: open
deps: []
links: []
created: 2026-11-08T16:27:49Z
type: feature
priority: 3
assignee: Alexis Purslane
parent: boo-fs0n
tags: [platform, macos, ios, ocr]
---
# Recognize scanned PDF pages on macOS and iOS

Only the Android runner implements the bookfin/ocr channel (recognize BGRA page to hOCR, close). lib/reader/platform_io.dart gives no text supply off Android, so a scanned PDF page on macOS shows the original page and the note 'This source page has no extracted text. The original page is available.' Cheapest path: a Swift worker on Apple's Vision text recognizer that implements the same channel contract and returns hOCR words with boxes, shared by the macOS and iOS runners. Alternative: bundle the Nix Tesseract and the pinned eng.traineddata, which pulls leptonica and image libraries into the app. Found in boo-gnx9.

## Acceptance Criteria

A scanned PDF from the fixture shows recognized English text in reflow on macOS, with the same cache and cancel rules as Android.

