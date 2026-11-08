---
id: tc-cl77
status: closed
deps: [tc-z7au]
links: []
created: 2026-11-08T19:23:13Z
type: feature
priority: 2
assignee: Alexis Purslane
parent: boo-b2ey
---
# Draw images in both themes and keep the fallbacks for unsupported images

Goal: images stay visible in the night theme where the book asks for it, and every image that cannot be drawn keeps its description.

Design section: "Coverage beyond the trial / Images and SVG".

Files: lib/reader/epub/css.dart, lib/reader/epub/prepare.dart, lib/reader/epub/paint.dart, test/reader/epub/image_test.dart.

Rules:
- The computed style gains filter: invert(N%). Other filters are ignored.
- Image items and inline image placeholders carry the filter. Paint draws such an image through a color matrix that inverts it by N percent.
- An image that fails to decode draws its alt text in its box. Without alt text it draws an outline.
- Admission already turns inline SVG into a span '[Unsupported image: label]' and an SVG wrapper of a JPEG into the JPEG. Test both through the native renderer.
- Keep the signatures from tc-nang.

## Design

docs/plans/native-epub-reader.md (epic boo-b2ey). Read the sections named in the description. The design decides the owners, interfaces and order. Ask the orchestrator before changing them.

## Acceptance Criteria

- In night, an image with filter: invert(100%) inside prefers-color-scheme: dark draws inverted. In cream it draws unchanged.
- An image that fails to decode draws its alt text.
- An inline SVG with an aria-label shows its label as text, and that text has places.
- An SVG wrapper of a JPEG draws the JPEG.


## Notes

**2026-11-08T23:32:49Z**

Style.invert holds filter: invert() from 0 to 1; several invert() compose (a + b - 2ab), other filters are ignored, and filter is not inherited. ImageItem and ImageRun carry a DrawnImage (path, invert, alt); ImageItem.path became ImageItem.image, and an image outside the publication now gets a decoration (path empty) so it draws its alt text. PageImages values became nullable: no entry = not decoded yet (outline), null = cannot decode (alt text, or outline without alt). layout.dart and page_source.dart changed only to carry DrawnImage. decodeImages (trial tests only) keeps its Map<String, ui.Image> result, so the trial files did not change. The broken-image test uses a palette PNG without PLTE: the image package reads it, Flutter refuses it. Real check: se-poetry's title page line art gets invert 1.0 in night, 0.0 in cream.
