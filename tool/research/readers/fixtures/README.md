# Fixture source and rights

These samples are not the user's book corpus.

`../fixtures.py` generates every binary and reading sample here except `pg11-kf8.mobi`.
The text and solid-color image are original Bookfin research material.
The fixture creator dedicates these generated samples to the public domain under CC0 1.0.
The dedication covers the fixture contents, not third-party engine code or fonts.
See https://creativecommons.org/publicdomain/zero/1.0/.

| Sample | Purpose | Source and license |
| --- | --- | --- |
| `river.epub` | EPUB3 spine, navigation, heading, local PNG | Generated, CC0 |
| `chapter.html` | Local image, internal link, deliberate script and remote image | Generated, CC0 |
| `chapter.md` | Heading, list, code block, local image, embedded script | Generated, CC0 |
| `dot.png` | Solid-color local asset | Generated with Pillow, CC0 |
| `mobi6-plain.mobi` | MOBI6, UTF-8 header, uncompressed content, embedded PNG | Generated PalmDB/MOBI bytes, CC0 |
| `mobi6-palmdoc.mobi` | MOBI6, PalmDOC compression marker and valid literal content, embedded PNG | Generated PalmDB/MOBI bytes, CC0 |
| `simple.pdf` | Two text pages, title candidates, embedded PNG | Generated with ReportLab, CC0. Standard Helvetica references, no embedded font |
| `columns.pdf` | Two columns, deliberately alternating right/left drawing order | Generated with ReportLab, CC0 |
| `table.pdf` | Row associations that the column heuristic loses | Generated with ReportLab, CC0 |
| `scanned.pdf` | Raster-only page, no hidden text layer, marker near bottom-right corner for whole-page rendering | Generated with Pillow/ReportLab, CC0 |
| `pg11-kf8.mobi` | Real standalone KF8, compressed text, embedded images and navigation | Project Gutenberg ebook 11, public domain in the United States, original ebook terms retained |

The separate KF8 sample is Lewis Carroll's *Alice's Adventures in Wonderland*, Project Gutenberg ebook 11.
The source is https://www.gutenberg.org/cache/epub/11/pg11-images-kf8.mobi.
Project Gutenberg lists the ebook as public domain in the United States.
Its redistribution terms and trademark conditions remain in the original ebook.
Do not assume the same copyright status outside the United States.
The original bytes are committed unchanged so that upstream regeneration does not break this corpus.
The research Nix flake exposes that tracked file as a Nix store input.
The converted EPUB stays in ignored `_out/`, not this repository.
The original ebook remains alongside the conversion in `_out/alice.mobi`.

The selected KF8 source was 255,506 bytes on November 1, 2026.
Its SHA-256 in Nix base32 is `1lpiz19420r2nxiw916ksjs6i0yv6q4rb2gj0a1yspfmmrli48fq`.
Its metadata identifies MOBI8, PalmDOC compression type 2, no encryption, and calibre 9.5.0 as the creator.
The original download was checked with `nix-prefetch-url` before inclusion.
Review replacement bytes and their rights before updating this versioned sample.
