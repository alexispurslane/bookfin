# Reader test fixtures

## Fonts

`outfit-ascii.woff` is a subset of `assets/fonts/Outfit.ttf`. The subset holds the printable ASCII characters (U+0020 to U+007E), with no hinting and no layout features. fontTools 4.63.0 made it:

```sh
pyftsubset assets/fonts/Outfit.ttf --unicodes="U+0020-007E" --no-hinting --layout-features="" --flavor=woff --output-file=outfit-ascii.woff
```

The tests put it in a book as the book's own font. The reader font covers every character of it, so the book needs no font of its own and draws in the reader font.

`outfit-star.woff` is a book's own font that covers one character that the reader font lacks: U+2605 BLACK STAR. The star glyph is a copy of Outfit's "O" with an advance of exactly two em, so a test can tell by the width which font drew the star. The font also holds the printable ASCII characters. Like many real fonts, it maps U+000D, U+200D and U+FEFF, which draw nothing, to its space glyph. fontTools 4.63.0 made it with `tool/reader/book_font_fixture.py`:

```sh
nix shell nixpkgs#python3Packages.fonttools --command python3 tool/reader/book_font_fixture.py
```

Outfit is under the SIL Open Font License 1.1, in `OFL-Outfit.txt`.

## Standard Ebooks style sheet

`se-core.css` is an excerpt of the `core.css` that every Standard Ebooks book holds. Standard Ebooks puts its work in the public domain (CC0 1.0). The excerpt keeps the `@namespace epub` rule, the heading rules and the verse rules.
