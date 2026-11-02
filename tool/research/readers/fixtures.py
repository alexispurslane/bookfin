"""Create small, original CC0 fixtures. No user books are used."""

import io
from pathlib import Path
import struct
import zipfile

from PIL import Image, ImageDraw
from reportlab.pdfgen import canvas


ROOT = Path(__file__).parent
FIXTURES = ROOT / "fixtures"
BODY = "The river follows the old road. A reader can change the text size without changing the saved source location."


def make_mobi(destination, compression):
    content = b'<html><head><title>Generated river</title></head><body><h1>River chapter</h1><p>The river follows the old road.</p><img recindex="00001"/></body></html>'
    encoded = content
    if compression == 2:
        encoded = b"".join(bytes([1, value]) if value < 9 or value >= 128 else bytes([value]) for value in content)
    header = bytearray(232)
    header[:4] = b"MOBI"
    for offset, value in [(4, 232), (8, 2), (12, 65001), (16, 73), (20, 6), (64, 2), (68, 248), (72, 9), (76, 9), (88, 6), (92, 2), (152, 0xFFFFFFFF), (228, 0xFFFFFFFF)]:
        struct.pack_into(">I", header, offset, value)
    for offset in (24, 28, 32, 36, 40, 44, 48, 52, 56, 60):
        struct.pack_into(">I", header, offset, 0xFFFFFFFF)
    struct.pack_into(">H", header, 176, 1)
    struct.pack_into(">H", header, 178, 1)
    records = [struct.pack(">HHIHHI", compression, 0, len(content), 1, 4096, 0) + header + b"River CC0", encoded, (FIXTURES / "dot.png").read_bytes()]
    database = bytearray(78)
    database[:9] = b"River CC0"
    database[60:68] = b"BOOKMOBI"
    struct.pack_into(">H", database, 76, len(records))
    offset = 78 + 8 * len(records) + 2
    table = bytearray()
    for number, record in enumerate(records):
        table += struct.pack(">II", offset, number * 2)
        offset += len(record)
    destination.write_bytes(database + table + b"\0\0" + b"".join(records))


def generate():
    FIXTURES.mkdir(exist_ok=True)
    Image.new("RGB", (24, 24), "#895c3a").save(FIXTURES / "dot.png")
    simple = canvas.Canvas(str(FIXTURES / "simple.pdf"), pagesize=(612, 792), invariant=1)
    for page in range(2):
        simple.setFont("Helvetica-Bold", 24)
        simple.drawString(36, 740, f"River chapter {page + 1}")
        simple.setFont("Helvetica", 12)
        for number, line in enumerate(["The river follows the old road.", "A reader can change the text size without changing", "the saved source location."]):
            simple.drawString(36, 690 - number * 18, line)
        simple.drawImage(str(FIXTURES / "dot.png"), 36, 540, 48, 48)
        simple.showPage()
    simple.save()
    columns = canvas.Canvas(str(FIXTURES / "columns.pdf"), pagesize=(612, 792), invariant=1)
    columns.setFont("Helvetica-Bold", 24)
    columns.drawString(36, 740, "Two columns")
    columns.setFont("Helvetica", 12)
    for number in range(3):
        columns.drawString(330, 690 - number * 18, f"Right {number + 1}: the journey ends.")
        columns.drawString(36, 690 - number * 18, f"Left {number + 1}: the journey begins.")
    columns.save()
    table = canvas.Canvas(str(FIXTURES / "table.pdf"), pagesize=(612, 792), invariant=1)
    table.setFont("Helvetica", 12)
    for number, (label, amount) in enumerate([("Item", "Amount"), ("Apple", "12"), ("Pear", "34")]):
        table.drawString(36, 740 - number * 20, label)
        table.drawString(330, 740 - number * 20, amount)
    table.save()
    scan = Image.new("RGB", (612, 792), "white")
    ImageDraw.Draw(scan).text((36, 60), "This page has pixels, not a PDF text layer.", fill="black", font_size=22)
    ImageDraw.Draw(scan).rectangle((560, 720, 584, 744), fill="#895c3a")
    scanned = canvas.Canvas(str(FIXTURES / "scanned.pdf"), pagesize=(612, 792), invariant=1)
    buffer = io.BytesIO()
    scan.save(buffer, format="PNG")
    from reportlab.lib.utils import ImageReader
    scanned.drawImage(ImageReader(buffer), 0, 0, 612, 792)
    scanned.save()
    (FIXTURES / "chapter.html").write_text('<h1 id="river">River chapter</h1><p>' + BODY + '</p><img src="dot.png"/><a href="#river">Return</a><script>fetch("https://example.invalid")</script><img src="https://example.invalid/track" onerror="alert(1)"/>')
    (FIXTURES / "chapter.md").write_text('# River chapter\n\n' + BODY + '\n\n- Follow the river\n- Return home\n\n```text\nA code block\n```\n\n![River](dot.png)\n\n<script>alert(1)</script>\n')
    with zipfile.ZipFile(FIXTURES / "river.epub", "w") as archive:
        def write_entry(name, content):
            archive.writestr(zipfile.ZipInfo(name, (2026, 11, 1, 0, 0, 0)), content)
        write_entry("mimetype", "application/epub+zip")
        write_entry("META-INF/container.xml", '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0"><rootfiles><rootfile full-path="OEBPS/book.opf" media-type="application/oebps-package+xml"/></rootfiles></container>')
        write_entry("OEBPS/book.opf", '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">urn:bookfin:river-cc0</dc:identifier><dc:title>River</dc:title><dc:language>en</dc:language><meta property="dcterms:modified">2026-11-01T00:00:00Z</meta></metadata><manifest><item id="chapter" href="chapter.xhtml" media-type="application/xhtml+xml"/><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/><item id="dot" href="dot.png" media-type="image/png"/></manifest><spine><itemref idref="chapter"/></spine></package>')
        write_entry("OEBPS/chapter.xhtml", '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>River</title></head><body><h1 id="river">River chapter</h1><p>' + BODY + '</p><img src="dot.png" alt="River"/></body></html>')
        write_entry("OEBPS/nav.xhtml", '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>Contents</title></head><body><nav epub:type="toc"><ol><li><a href="chapter.xhtml#river">River chapter</a></li></ol></nav></body></html>')
        write_entry("OEBPS/dot.png", (FIXTURES / "dot.png").read_bytes())
    make_mobi(FIXTURES / "mobi6-plain.mobi", 1)
    make_mobi(FIXTURES / "mobi6-palmdoc.mobi", 2)


if __name__ == "__main__":
    generate()
