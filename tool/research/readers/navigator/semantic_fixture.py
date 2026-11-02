import zipfile


def make_semantic_epub(destination, root):
    entries = {
        'mimetype': 'application/epub+zip',
        'META-INF/container.xml': '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0"><rootfiles><rootfile full-path="OEBPS/book.opf" media-type="application/oebps-package+xml"/></rootfiles></container>',
        'OEBPS/book.opf': '''<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">bookfin-semantic-probe</dc:identifier><dc:title>Semantic probe</dc:title><dc:language>fr</dc:language><meta property="dcterms:modified">2026-11-02T00:00:00Z</meta></metadata><manifest>
<item id="nav" href="nav.xhtml" properties="nav" media-type="application/xhtml+xml"/>
<item id="one" href="Text/one.xhtml" media-type="application/xhtml+xml"/>
<item id="two" href="Text/two.xhtml" media-type="application/xhtml+xml"/>
<item id="css" href="Styles/book.css" media-type="text/css"/>
<item id="font" href="Fonts/source-serif.woff2" media-type="font/woff2"/>
<item id="image" href="Images/dot.png" media-type="image/png"/>
</manifest><spine><itemref idref="one"/><itemref idref="two"/></spine></package>''',
        'OEBPS/nav.xhtml': '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>Contents</title></head><body><nav epub:type="toc"><ol><li><a href="Text/one.xhtml#heading">Édition stable</a><ol><li><a href="Text/two.xhtml#note">Note</a></li></ol></li></ol></nav></body></html>',
        'OEBPS/Text/one.xhtml': '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" lang="fr"><head><title>First chapter</title><link rel="stylesheet" href="../Styles/book.css"/></head><body><h1 id="heading">Édition stable</h1><p>🦦 A source position survives text size changes.</p><p>A phrase crosses <em>inline emphasis</em> in this sentence.</p><p>Repeatable phrase. Repeatable phrase.</p><p lang="ar" dir="rtl">كتاب</p><img src="../Images/dot.png" alt="A sepia square"/><a epub:type="noteref" href="two.xhtml#note">Read note</a></body></html>',
        'OEBPS/Text/two.xhtml': '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>Note</title></head><body><aside id="note" epub:type="footnote"><p>A local footnote.</p><a href="one.xhtml#heading">Return to heading</a></aside></body></html>',
        'OEBPS/Styles/book.css': '@font-face{font-family:BookSerif;src:url("../Fonts/source-serif.woff2") format("woff2")}body{font-family:BookSerif,serif}h1{font-size:1.5em}',
        'OEBPS/Fonts/source-serif.woff2': (root / 'docs/mockups/fonts/source-serif-4-latin.woff2').read_bytes(),
        'OEBPS/Fonts/OFL-Source-Serif-4.txt': (root / 'docs/mockups/fonts/OFL-Source-Serif-4.txt').read_bytes(),
        'OEBPS/Images/dot.png': (root / 'tool/research/readers/fixtures/dot.png').read_bytes(),
    }
    with zipfile.ZipFile(destination, 'w') as archive:
        for name, content in entries.items():
            archive.writestr(zipfile.ZipInfo(name, (2026, 11, 2, 0, 0, 0)), content)
