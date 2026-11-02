"""Measure existing research engines on pinned real works, not production code."""

from collections import Counter
import hashlib
from io import BytesIO
import json
from pathlib import Path, PurePosixPath
import posixpath
import re
import subprocess
from urllib.parse import unquote, urlsplit
import zipfile

from lxml import etree, html
import markdown
from PIL import Image
from reportlab.pdfgen import canvas

from corpus_inputs import verify_input
from proof import anchor_for, extract_pdf, reflow_pdf, resolve_anchor, safe_html
from pdf_text_quality import assess_page


ROOT = Path(__file__).resolve().parent
OUT = ROOT / "_out/corpus"


def fingerprint(path):
    with path.open("rb") as source:
        return {"size_bytes": path.stat().st_size,
                "sha256": hashlib.file_digest(source, "sha256").hexdigest()}


def inspect_epub(path, phrases):
    with zipfile.ZipFile(path) as archive:
        container = etree.fromstring(archive.read("META-INF/container.xml"))
        package_path = container.xpath("//*[local-name()='rootfile']/@full-path")[0]
        package = etree.fromstring(archive.read(package_path))
        directory = posixpath.dirname(package_path)
        resources = {item.get("id"): item for item in package.xpath("//*[local-name()='manifest']/*")}
        spine = package.xpath("//*[local-name()='spine']/*/@idref")
        documents = {}
        headings = []
        ordered_text = []
        for resource in resources.values():
            name = posixpath.normpath(posixpath.join(directory, unquote(resource.get("href"))))
            if resource.get("media-type") in {"application/xhtml+xml", "text/html"}:
                documents[name] = html.fromstring(archive.read(name))
        for reference in spine:
            resource = resources[reference]
            name = posixpath.normpath(posixpath.join(directory, unquote(resource.get("href"))))
            tree = documents[name]
            ordered_text.append(" ".join(tree.text_content().split()))
            headings.extend(" ".join(node.text_content().split()) for node in tree.xpath("//h1|//h2|//h3"))
        text = "\n".join(ordered_text)
        missing = []
        links = 0
        for name, tree in documents.items():
            for attribute in tree.xpath("//a/@href|//img/@src|//image/@*[local-name()='href']"):
                parsed = urlsplit(attribute)
                if parsed.scheme or parsed.netloc:
                    continue
                links += 1
                target = posixpath.normpath(posixpath.join(posixpath.dirname(name), unquote(parsed.path))) if parsed.path else name
                if target not in archive.namelist():
                    missing.append({"from": name, "reference": attribute, "reason": "missing resource"})
                elif parsed.fragment and target in documents and not documents[target].xpath("//*[@id=$value or @name=$value]", value=unquote(parsed.fragment)):
                    missing.append({"from": name, "reference": attribute, "reason": "missing fragment"})
        images = []
        for resource in resources.values():
            mime = resource.get("media-type", "")
            if mime.startswith("image/"):
                name = posixpath.normpath(posixpath.join(directory, unquote(resource.get("href"))))
                image = {"path": name, "mime": mime, "size_bytes": len(archive.read(name))}
                if mime != "image/svg+xml":
                    try:
                        with Image.open(BytesIO(archive.read(name))) as raster:
                            raster.load()
                            image["decoded_size_pixels"] = list(raster.size)
                    except Exception as error:
                        image["decode_error"] = str(error)
                images.append(image)
        return {
            **fingerprint(path), "archive_entries": len(archive.namelist()),
            "epub_version": package.get("version"), "spine_items": len(spine),
            "spine_text_characters": len(text), "headings": headings,
            "expected_phrases": {phrase: phrase.casefold() in text.casefold() for phrase in phrases},
            "local_references": links, "broken_references": missing,
            "media_types": dict(Counter(item.get("media-type") for item in resources.values())),
            "images": images,
        }


def inspect_pdf(sample, path):
    blocks = extract_pdf(path)
    text = "\n".join(block["text"] for block in blocks)
    (OUT / f"{sample['id']}-geometry.txt").write_text(text + "\n")
    metadata = subprocess.run(["pdfinfo", str(path)], check=True, text=True, capture_output=True, timeout=30).stdout
    (OUT / f"{sample['id']}-pdfinfo.txt").write_text(metadata)
    pages = int(re.search(r"Pages:\s+(\d+)", metadata)[1])
    selected = 4 if sample["id"] == "nist-text-pdf" else 0 if sample["id"] == "census-multicolumn-pdf" else 8
    chosen = [block for block in blocks if block["page"] == selected]
    decisions = {str(page + 1): assess_page([block for block in blocks if block["page"] == page]) for page in range(pages)}
    decision = decisions[str(selected + 1)]
    layouts = {}
    expected_text = re.sub(r"\s+", "", "".join(block["text"] for block in chosen))
    for width in (360, 720):
        destination = OUT / f"{sample['id']}-reflow-{width}.pdf"
        if decision["view"] != "reflow":
            destination.unlink(missing_ok=True)
            layouts[str(width)] = {"status": "original-page", "text_status": decision["status"], "reasons": decision["reasons"]}
            continue
        lines = reflow_pdf(chosen, destination, width)
        extracted = subprocess.run(["pdftotext", "-raw", str(destination), "-"], check=True, capture_output=True, text=True, timeout=30).stdout
        actual_text = re.sub(r"\s+", "", extracted)
        layouts[str(width)] = {
            "status": "candidate-not-fidelity-validated",
            "paragraph_height_derived_line_count": lines,
            "source_nonspace_characters": len(expected_text),
            "reflow_nonspace_characters": len(actual_text),
            "nonspace_text_matches_extracted_source": actual_text == expected_text,
            "missing_character_counts": dict(Counter(expected_text) - Counter(actual_text)),
        }
    phrase = next((block["text"] for block in chosen if len(block["text"]) > 20), None)
    anchor = anchor_for(path, blocks, phrase) if phrase else None
    source_prefix = OUT / f"{sample['id']}-source"
    subprocess.run(["pdftoppm", "-f", str(selected + 1), "-l", str(selected + 1), "-singlefile", "-scale-to", "720", "-png", str(path), str(source_prefix)], check=True, capture_output=True, timeout=30)
    subprocess.run(["pdftotext", "-f", str(selected + 1), "-l", str(selected + 1), "-layout", str(path), str(OUT / f"{sample['id']}-poppler-layout.txt")], check=True, capture_output=True, timeout=30)
    return {
        "pages": pages, "blocks": len(blocks), "extracted_characters": len(text),
        "blocks_by_page_1_based": {str(page + 1): sum(block["page"] == page for block in blocks) for page in range(pages)},
        "expected_phrases": {phrase: phrase.casefold() in text.casefold() for phrase in sample["expected_phrases"]},
        "sampled_page_1_based": selected + 1, "sampled_page_lines": [block["text"] for block in chosen],
        "sampled_page_layout_by_width_pdf_points": layouts,
        "text_quality_by_page_1_based": {
            page: {**{key: value for key, value in decision.items() if key != "paragraphs"},
                   "paragraph_candidates": len(decision["paragraphs"])}
            for page, decision in decisions.items()
        },
        "source_anchor": anchor, "anchor_resolves": resolve_anchor(path, blocks, anchor) == phrase if phrase else None,
        "anchor_candidate_criterion": "First sampled-page block longer than 20 characters; null when none exists, not a navigation test.",
        "heading_candidates": [{"page_1_based": block["page"] + 1, "text": block["text"]} for block in blocks if block["heading"]][:20],
    }


def main():
    samples = json.loads((ROOT / "corpus-manifest.json").read_text())["samples"]
    OUT.mkdir(parents=True, exist_ok=True)
    results = {"scope": "host-only; no OCR or production reader", "samples": {}}
    for sample in samples:
        path = OUT / "originals" / sample["filename"]
        verify_input(path, sample)
        observation = {"input": fingerprint(path)}
        results["samples"][sample["id"]] = observation
        if sample["format"] in {"epub", "mobi"}:
            if sample["format"] == "mobi":
                metadata = subprocess.run(["mobitool", "-i", str(path)], capture_output=True, text=True, timeout=45)
                (OUT / f"{sample['id']}-metadata.txt").write_text(metadata.stdout + metadata.stderr)
                converted = OUT / "converted"
                converted.mkdir(exist_ok=True)
                conversion = subprocess.run(["mobitool", "-e", "-o", str(converted), str(path)], capture_output=True, text=True, timeout=45)
                (OUT / f"{sample['id']}-conversion.txt").write_text(conversion.stdout + conversion.stderr)
                observation["conversion_exit"] = conversion.returncode
                observation["mobi_version"] = re.search(r"file version: (\d+)", metadata.stdout)[1]
                observation["compression_type"] = re.search(r"compression type: (\d+)", metadata.stdout)[1]
                observation["encryption_type"] = re.search(r"encryption type: (\d+)", metadata.stdout)[1]
                path = converted / f"{path.stem}.epub"
                if conversion.returncode or not path.exists():
                    observation["failure"] = "conversion did not produce an EPUB"
                    continue
            observation["epub"] = inspect_epub(path, sample["expected_phrases"])
        elif sample["format"] == "html-zip":
            directory = OUT / "html"
            directory.mkdir(exist_ok=True)
            with zipfile.ZipFile(path) as archive:
                if len(archive.infolist()) > 1000 or sum(entry.file_size for entry in archive.infolist()) > 16_000_000:
                    raise ValueError("HTML research archive exceeds inspection bounds")
                for entry in archive.infolist():
                    name = PurePosixPath(entry.filename)
                    if name.is_absolute() or ".." in name.parts:
                        raise ValueError("Unexpected HTML research archive path")
                archive.extractall(directory)
            source = next(directory.rglob("*.html"))
            original = html.fromstring(source.read_bytes())
            filtered = safe_html(source.read_text(), source.parent)
            (OUT / "dracula-passive.html").write_text(filtered)
            passive = html.fromstring(filtered)
            observation["html"] = {
                "source_path": str(source.relative_to(OUT)),
                "source_headings": len(original.xpath("//h1|//h2|//h3")),
                "retained_headings": len(passive.xpath("//h1|//h2|//h3")),
                "source_local_images": original.xpath("//img/@src"),
                "retained_local_images": passive.xpath("//img/@src"),
                "source_links": len(original.xpath("//a[@href]")),
                "retained_links": len(passive.xpath("//a[@href]")),
                "source_style_elements": len(original.xpath("//style")),
                "retained_style_elements": len(passive.xpath("//style")),
                "expected_phrases": {phrase: phrase.casefold() in passive.text_content().casefold() for phrase in sample["expected_phrases"]},
            }
        elif sample["format"] == "text-to-markdown":
            document = "# Shakespeare's Sonnets\n\n```text\n" + path.read_text(encoding="utf-8-sig").rstrip() + "\n```\n"
            destination = OUT / "sonnets.md"
            destination.write_text(document)
            filtered = safe_html(markdown.markdown(document, extensions=["fenced_code"]), OUT)
            (OUT / "sonnets-passive.html").write_text(filtered)
            observation["markdown"] = {"derived_input": fingerprint(destination), "expected_phrases": {phrase: phrase in html.fromstring(filtered).text_content() for phrase in sample["expected_phrases"]}, "derivation": "Whole public-domain source, including Gutenberg terms, in one fenced text block under a title; not publisher Markdown."}
        else:
            observation["pdf"] = inspect_pdf(sample, path)
        print(f"measured {sample['id']}", flush=True)
    raster_path = OUT / "raven-raster-only.pdf"
    source_image = OUT / "raven-1873-scan-source.png"
    with Image.open(source_image) as image:
        width, height = image.size
    output = canvas.Canvas(str(raster_path), pagesize=(width, height), invariant=1)
    output.drawImage(str(source_image), 0, 0, width=width, height=height)
    output.save()
    results["raven_raster_only_derivative"] = {**fingerprint(raster_path), "source_id": "raven-1873-scan", "source_page_1_based": 9, "extracted_blocks": len(extract_pdf(raster_path)), "derivation": "Render the real scanned page at 720 pixels; wrap that image in a new PDF without a text layer. No OCR."}
    results["truncated_inputs"] = {}
    for filename, length in [("frankenstein.mobi", 96), ("nist-cloud.pdf", 512)]:
        source = OUT / "originals" / filename
        destination = OUT / f"truncated-{filename}"
        destination.write_bytes(source.read_bytes()[:length])
        if filename.endswith(".mobi"):
            command = ["mobitool", "-e", "-o", str(OUT), str(destination)]
        else:
            command = ["python", "-c", "import sys; from proof import extract_pdf; print(len(extract_pdf(sys.argv[1])))", str(destination)]
        attempt = subprocess.run(command, capture_output=True, text=True, timeout=45)
        results["truncated_inputs"][filename] = {
            **fingerprint(destination), "exit": attempt.returncode,
            "output": (attempt.stdout + attempt.stderr)[-1500:],
            "produced_epub": destination.with_suffix(".epub").exists() if filename.endswith(".mobi") else None,
        }
    (OUT / "python-observations.json").write_text(json.dumps(results, indent=2, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    main()
