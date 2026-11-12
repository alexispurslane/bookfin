"""Makes test/reader/epub/fixtures/outfit-star.woff.

The fixture is a book's own font that covers one character that the reader
font (Source Serif 4) lacks: U+2605 BLACK STAR. Its star glyph is a copy of
Outfit's "O", with an advance of exactly two em, so that a test can tell by
width alone which font drew the star. It also holds the printable ASCII
characters, which the reader font has. Like many real fonts, it maps three
characters that draw nothing to its space glyph: U+000D CARRIAGE RETURN,
U+200D ZERO WIDTH JOINER and U+FEFF ZERO WIDTH NO-BREAK SPACE. The reader
font lacks those three, but no text needs a font for them.

Run it from the repository root, with fontTools on the path:

    nix shell nixpkgs#python3Packages.fonttools --command \
        python3 tool/reader/book_font_fixture.py
"""

import copy

from fontTools import subset
from fontTools.ttLib import TTFont

SOURCE = "assets/fonts/Outfit.ttf"
OUTPUT = "test/reader/epub/fixtures/outfit-star.woff"
STAR = 0x2605
INVISIBLE = (0x000D, 0x200D, 0xFEFF)

options = subset.Options()
options.hinting = False
options.layout_features = []
options.flavor = None
font = TTFont(SOURCE)
subsetter = subset.Subsetter(options)
subsetter.populate(unicodes=range(0x20, 0x7F))
subsetter.subset(font)

# A variable font keeps its outlines in gvar too. The star needs none of it.
for table in ("fvar", "gvar", "avar", "STAT", "HVAR", "MVAR"):
    if table in font:
        del font[table]

glyphs = font["glyf"]
order = font.getGlyphOrder()
source = font.getBestCmap()[ord("O")]
glyphs.glyphs["star"] = copy.deepcopy(glyphs[source])
font.setGlyphOrder(order + ["star"])
glyphs.glyphOrder = font.getGlyphOrder()
em = font["head"].unitsPerEm
_, side = font["hmtx"][source]
font["hmtx"]["star"] = (2 * em, side)
for table in font["cmap"].tables:
    if table.isUnicode():
        table.cmap[STAR] = "star"
        for code in INVISIBLE:
            table.cmap[code] = table.cmap[0x20]
font.flavor = "woff"
font.save(OUTPUT)
print(f"wrote {OUTPUT}: {len(font.getGlyphOrder())} glyphs, {em} units per em")
