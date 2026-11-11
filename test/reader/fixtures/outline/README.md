# PDF outline fixtures

`parts-book.pdf` is a born-digital A5 book of 9 pages. The tests of the PDF text outline use it (`test/reader/pdf_outline_test.dart`, ticket t9-nl30). Ticket t9-nl30 wrote `parts-book.typ` and dedicates it and the PDF to the public domain under CC0 1.0 (https://creativecommons.org/publicdomain/zero/1.0/). The PDF embeds subsets of Libertinus Serif, under the SIL Open Font License 1.1. Typst bundles the font.

- Page 1 is a title page.
- The bookmarks nest two chapters inside each of two parts: "Part One: Water" holds "Chapter 1: Clouds" and "Chapter 2: Rain", and "Part Two: Air" holds "Chapter 3: Wind" and "Chapter 4: Snow". Typst makes a bookmark of each heading, with an /XYZ destination at the heading's top.
- Part One and chapter 1 start at the top of page 2. Chapter 2 starts partway down page 3, under six sentences of chapter 1.
- Page 5 holds a drawing of circles in a frame, and no text.
- Part Two and chapter 3 start at the top of page 6. Chapter 4 starts at the top of page 8.
- Its SHA-256 is `d7ef8c559fc4b9e13bc0b50c8e73de06361700762161aa39121bfff7d3392e4f`. The Typst that the flake pins (0.15.1) makes the same bytes again.

To make it again, run this in the dev shell, in this folder:

```sh
typst compile --ignore-system-fonts parts-book.typ parts-book.pdf
```
