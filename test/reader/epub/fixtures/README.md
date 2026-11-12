# Reader test fixtures

## Fonts

`outfit-ascii.woff` is a subset of `assets/fonts/Outfit.ttf`. The subset holds the printable ASCII characters (U+0020 to U+007E), with no hinting and no layout features. fontTools 4.63.0 made it:

```sh
pyftsubset assets/fonts/Outfit.ttf --unicodes="U+0020-007E" --no-hinting --layout-features="" --flavor=woff --output-file=outfit-ascii.woff
```

The tests put it in a book as the book's own font. The reader never reads it, so the book draws in the reader font. Outfit is under the SIL Open Font License 1.1, in `OFL-Outfit.txt`.

## Standard Ebooks style sheet

`se-core.css` is an excerpt of the `core.css` that every Standard Ebooks book holds. Standard Ebooks puts its work in the public domain (CC0 1.0). The excerpt keeps the `@namespace epub` rule, the heading rules and the verse rules.
