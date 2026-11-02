"""Research boundary for extracted reading content; not production reader code."""

import ctypes
from functools import cache
import hashlib
from html import escape
import os
from pathlib import Path
from statistics import median
from urllib.parse import unquote, urlsplit

import bleach
from lxml import html
from reportlab.pdfgen import canvas
from reportlab.platypus import Paragraph
from reportlab.lib.styles import ParagraphStyle


@cache
def pdfium():
    library = ctypes.CDLL(os.environ["PDFIUM_LIBRARY"])
    pointer = ctypes.c_void_p
    integer = ctypes.c_int
    real = ctypes.c_double
    signatures = {
        "FPDF_InitLibrary": (None, []),
        "FPDF_LoadDocument": (pointer, [ctypes.c_char_p, ctypes.c_char_p]),
        "FPDF_CloseDocument": (None, [pointer]),
        "FPDF_GetPageCount": (integer, [pointer]),
        "FPDF_LoadPage": (pointer, [pointer, integer]),
        "FPDF_ClosePage": (None, [pointer]),
        "FPDF_GetPageWidth": (real, [pointer]),
        "FPDFText_LoadPage": (pointer, [pointer]),
        "FPDFText_ClosePage": (None, [pointer]),
        "FPDFText_CountChars": (integer, [pointer]),
        "FPDFText_GetUnicode": (ctypes.c_uint, [pointer, integer]),
        "FPDFText_GetFontSize": (real, [pointer, integer]),
        "FPDFText_GetCharOrigin": (integer, [pointer, integer, ctypes.POINTER(real), ctypes.POINTER(real)]),
        "FPDFText_GetCharBox": (integer, [pointer, integer] + [ctypes.POINTER(real)] * 4),
    }
    for name, (result, arguments) in signatures.items():
        function = getattr(library, name)
        function.restype = result
        function.argtypes = arguments
    library.FPDF_InitLibrary()
    return library


def extract_pdf(path):
    library = pdfium()
    document = library.FPDF_LoadDocument(os.fsencode(path), None)
    if not document:
        raise ValueError("PDFium could not open the PDF")
    blocks = []
    try:
        for page_number in range(library.FPDF_GetPageCount(document)):
            page = library.FPDF_LoadPage(document, page_number)
            if not page:
                raise ValueError("PDFium could not load a source page")
            text_page = library.FPDFText_LoadPage(page)
            try:
                lines = {}
                for index in range(library.FPDFText_CountChars(text_page)):
                    value = library.FPDFText_GetUnicode(text_page, index)
                    if not value or chr(value) in "\r\n":
                        continue
                    origin_x, origin_y = ctypes.c_double(), ctypes.c_double()
                    library.FPDFText_GetCharOrigin(text_page, index, ctypes.byref(origin_x), ctypes.byref(origin_y))
                    left, right, bottom, top = [ctypes.c_double() for _ in range(4)]
                    library.FPDFText_GetCharBox(text_page, index, *[ctypes.byref(value) for value in (left, right, bottom, top)])
                    character = {"text": chr(value), "index": index, "x": origin_x.value, "right": right.value, "size": library.FPDFText_GetFontSize(text_page, index), "bbox": [left.value, bottom.value, right.value, top.value]}
                    lines.setdefault(round(origin_y.value), []).append(character)
                page_blocks = []
                for baseline, characters in lines.items():
                    groups = [[]]
                    for character in sorted(characters, key=lambda value: value["x"]):
                        if groups[-1] and character["x"] - groups[-1][-1]["right"] > 18:
                            groups.append([])
                        groups[-1].append(character)
                    for group in groups:
                        while group and group[0]["text"].isspace():
                            group.pop(0)
                        while group and group[-1]["text"].isspace():
                            group.pop()
                        if group:
                            page_blocks.append({"page": page_number, "baseline": baseline, "x": group[0]["x"], "size": median(character["size"] for character in group), "text": "".join(character["text"] for character in group), "source_indices": [character["index"] for character in group], "boxes": [character["bbox"] for character in group]})
                body_size = median(block["size"] for block in page_blocks) if page_blocks else 0
                for block in page_blocks:
                    block["heading"] = block["size"] > body_size * 1.3
                midpoint = library.FPDF_GetPageWidth(page) / 2
                page_blocks.sort(key=lambda block: (0 if block["heading"] else 1 if block["x"] < midpoint else 2, -block["baseline"], block["x"]))
                blocks.extend(page_blocks)
            finally:
                library.FPDFText_ClosePage(text_page)
                library.FPDF_ClosePage(page)
    finally:
        library.FPDF_CloseDocument(document)
    return blocks


def anchor_for(path, blocks, phrase):
    for block in blocks:
        offset = block["text"].find(phrase)
        if offset >= 0:
            return {"sha256": hashlib.sha256(Path(path).read_bytes()).hexdigest(), "page": block["page"], "character": block["source_indices"][offset], "bbox": block["boxes"][offset]}
    return None


def resolve_anchor(path, blocks, anchor):
    if anchor is None or hashlib.sha256(Path(path).read_bytes()).hexdigest() != anchor["sha256"]:
        return None
    for block in blocks:
        if block["page"] == anchor["page"] and anchor["character"] in block["source_indices"]:
            return block["text"][block["source_indices"].index(anchor["character"]):]
    return None


def safe_html(content, root):
    tree = html.fragment_fromstring(content, create_parent="div")
    for element in tree.xpath(".//script|.//style|.//iframe|.//object|.//embed|.//svg|.//math|.//form|.//base|.//link|.//meta"):
        element.drop_tree()

    def allowed_attribute(tag, name, value):
        if name in {"id", "alt", "title"}:
            return True
        if (tag, name) not in {("a", "href"), ("img", "src")}:
            return False
        decoded = value
        for _ in range(8):
            previous, decoded = decoded, unquote(decoded)
            if previous == decoded:
                break
        if "%" in decoded or "\\" in decoded or any(ord(character) < 32 for character in decoded):
            return False
        parsed = urlsplit(decoded)
        if parsed.scheme or parsed.netloc or parsed.query:
            return False
        if not parsed.path:
            return tag == "a" and bool(parsed.fragment)
        book_root = Path(root).resolve()
        target = (book_root / parsed.path).resolve()
        return target.is_relative_to(book_root) and target.is_file()

    return bleach.clean(html.tostring(tree, encoding="unicode"), tags={"h1", "h2", "h3", "h4", "h5", "h6", "p", "a", "img", "strong", "em", "ul", "ol", "li", "pre", "code", "br", "blockquote", "table", "thead", "tbody", "tr", "th", "td"}, attributes=allowed_attribute, protocols={"http", "https"}, strip=True)


def reflow_pdf(blocks, destination, width):
    if width < 120:
        raise ValueError("Reflow width must leave space for text")
    output = canvas.Canvas(str(destination), pagesize=(width, 792), invariant=1)
    baseline = 760
    line_count = 0
    for block in blocks:
        style = ParagraphStyle("reading", fontName="Helvetica-Bold" if block["heading"] else "Helvetica", fontSize=24 if block["heading"] else 18, leading=30 if block["heading"] else 25)
        paragraph = Paragraph(escape(block["text"]), style)
        _, height = paragraph.wrap(width - 32, 720)
        if baseline - height < 32:
            output.showPage()
            baseline = 760
        paragraph.drawOn(output, 16, baseline - height)
        line_count += round(height / style.leading)
        baseline -= height + 10
    output.save()
    return line_count
