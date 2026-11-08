# Reader test fixtures

## Fonts

The three `outfit-ascii` files are one subset of `assets/fonts/Outfit.ttf`. The subset holds the printable ASCII characters (U+0020 to U+007E), with no hinting and no layout features. fontTools 4.63.0 made them:

```sh
pyftsubset assets/fonts/Outfit.ttf --unicodes="U+0020-007E" --no-hinting --layout-features="" --output-file=outfit-ascii.ttf
pyftsubset assets/fonts/Outfit.ttf --unicodes="U+0020-007E" --no-hinting --layout-features="" --flavor=woff --output-file=outfit-ascii.woff
pyftsubset assets/fonts/Outfit.ttf --unicodes="U+0020-007E" --no-hinting --layout-features="" --flavor=woff2 --output-file=outfit-ascii.woff2
```

The WOFF file has zlib tables and stored tables, so a test of the WOFF conversion reads both kinds. Outfit is under the SIL Open Font License 1.1, in `OFL-Outfit.txt`.

## Standard Ebooks style sheet

`se-core.css` is an excerpt of the `core.css` that every Standard Ebooks book holds. Standard Ebooks puts its work in the public domain (CC0 1.0). The excerpt keeps the `@namespace epub` rule, the heading rules and the verse rules.
