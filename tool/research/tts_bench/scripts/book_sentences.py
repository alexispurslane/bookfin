"""Write one sentence per line from an EPUB's chapters, in reading order.

Usage: python3 -I book_sentences.py BOOK.epub OUT.txt
Long sentences are cut at clause punctuation so that each line stays well
under Kokoro's 510-token limit.
"""
import html
import re
import sys
import zipfile
import xml.etree.ElementTree as ET

book, out = sys.argv[1], sys.argv[2]
z = zipfile.ZipFile(book)
container = ET.fromstring(z.read("META-INF/container.xml"))
opf_path = container.find(".//{*}rootfile").get("full-path")
opf = ET.fromstring(z.read(opf_path))
base = opf_path.rsplit("/", 1)[0] + "/" if "/" in opf_path else ""
items = {i.get("id"): i.get("href") for i in opf.iter("{http://www.idpf.org/2007/opf}item")}
spine = [items[r.get("idref")] for r in opf.iter("{http://www.idpf.org/2007/opf}itemref")]

blocks = []
for href in spine:
    doc = z.read(base + href).decode("utf-8", "replace")
    doc = re.sub(r"(?is)<(script|style|head)\b.*?</\1>", " ", doc)
    for b in re.findall(r"(?is)<(?:p|h[1-6])\b[^>]*>(.*?)</(?:p|h[1-6])>", doc):
        text = html.unescape(re.sub(r"(?s)<[^>]+>", " ", b))
        text = re.sub(r"\s+", " ", text).strip()
        if text:
            blocks.append(text)

sentences = []
for b in blocks:
    for s in re.split(r"(?:(?<=[.!?])|(?<=[.!?][\"'”’]))\s+(?=[\"'“‘A-Z])", b):
        while len(s) > 300:
            cut = max(s.rfind(c, 0, 300) for c in ";:,")
            cut = cut if cut > 50 else 300
            sentences.append(s[: cut + 1].strip())
            s = s[cut + 1 :]
        if s.strip():
            sentences.append(s.strip())

with open(out, "w") as f:
    f.write("\n".join(sentences) + "\n")
print(len(sentences), "sentences,", sum(len(s.split()) for s in sentences), "words")
