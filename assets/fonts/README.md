# Bundled application fonts

The application bundles full variable TrueType files, not the mockup's Latin-only WOFF2 subsets.
A variable font stores several levels of boldness in one file.
Neither font needs a network request at runtime.
The SIL Open Font License texts accompany these files and appear in Flutter's license registry.

Source: `google/fonts`, commit `6c1dbe27dcf7d817d4b62cec033ba77fa8e2a5ec`.

| Asset | Upstream path | SHA-256 |
| --- | --- | --- |
| Outfit.ttf | ofl/outfit/Outfit[wght].ttf | fc7287273e66929776e2ba54f144fe699080bec29f61bf649d70d871468aeade |
| SourceSerif4.ttf | ofl/sourceserif4/SourceSerif4[opsz,wght].ttf | 97b2d4da6e3cb494b5a1e66ae176914d852ccabef49e0c02c0df25f3e39aca0b |
| NotoSansMath-Arrows.ttf | subset of ofl/notosansmath/NotoSansMath-Regular.ttf (3f495fe933c06786e4d5f6d86b8ee70b6753a68ee3b9d87528726de0f6e2c47d) | 7025135adc0d51f2de2d456f27c0dbca5f742f33efd8c0d86d5a32e21c1765e9 |

Outfit provides geometric headings and interface text.
Source Serif 4 provides book titles and reading text.
Source Serif 4 includes Latin, extended Latin, Greek, Cyrillic, and Vietnamese coverage.
NotoSansMath-Arrows.ttf holds only the Unicode arrow blocks of Noto Sans Math, as the family `Noto Sans Math Arrows`.
The reader draws an arrow that the book's face and Source Serif 4 both lack in this font, such as the leftwards arrow with hook (U+21A9) of a back link.
Without it, Android draws such an arrow with its color emoji font.
fontTools 4.63.0 made the subset with this command:

```sh
pyftsubset NotoSansMath-Regular.ttf --unicodes="U+2190-21FF,U+27F0-27FF,U+2900-297F,U+2B00-2B4F" --layout-features='*' --no-hinting --drop-tables+=MATH --output-file=NotoSansMath-Arrows.ttf
```

`OFL-Noto-Sans-Math.txt` is the license of Noto Sans Math from the same commit.
Flutter falls back to installed Android fonts for unsupported characters, including scripts outside those bundled fonts.
The theme names Roboto/Noto Sans and Noto Serif as fallback families.
Installed fonts depend on the Android device; this does not promise matching typography for every script.
Android must not download missing glyphs from a remote font service.
The secondary browser preview currently uses Flutter's remote framework fallback fonts; ticket `te-6x43` tracks removing that dependency.
Keep `docs/mockups/fonts` and the approved HTML reference unchanged.
