"""Reproduce bounded text-quality decisions without changing historical evidence."""

import argparse
import base64
from collections import Counter
from html import escape
import json
from pathlib import Path
import re
import subprocess

from PIL import Image

from corpus_inputs import verify_input
from corpus_probe import fingerprint
from pdf_text_quality import assess_page
from proof import anchor_for, extract_pdf, reflow_pdf, resolve_anchor


ROOT = Path(__file__).resolve().parent
RETAINED = ROOT / "evidence/corpus"
RASTER = ROOT / "evidence/text-quality/raven-raster-only.pdf"
RAVEN_ERRORS = [
    "The printed opening ONCE loses its decorative O in the existing text layer.",
    "The decorative title is misread in the existing text layer.",
]


def run(*arguments):
    return subprocess.run(arguments, check=True, capture_output=True, text=True, timeout=30).stdout


def render(path, page, destination):
    run("pdftoppm", "-f", str(page), "-l", str(page), "-singlefile", "-scale-to", "720", "-png", str(path), str(destination.with_suffix("")))
    with Image.open(destination) as image:
        image.thumbnail((480, 480), Image.Resampling.BICUBIC)
        image.save(destination)


def page_observation(path, page, blocks, source_errors=()):
    decision = assess_page(blocks, source_layer_errors=source_errors)
    ordered = sorted(blocks, key=lambda block: (-block["baseline"], block["x"]))
    return {
        **{key: value for key, value in decision.items() if key != "paragraphs"},
        "original_page": {**fingerprint(path), "page_1_based": page},
        "paragraph_candidates": [
            {"text": paragraph["text"], "heading_candidate": paragraph["heading"],
             "source_block_count": len(paragraph["source_blocks"])}
            for paragraph in decision["paragraphs"]
        ],
        "edge_blocks_top_to_bottom": [
            {"text": block["text"], "baseline_pdf_points": block["baseline"],
             "first_source_character": block["source_indices"][0]}
            for block in (ordered[:3] + ordered[-3:])
        ],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "_out/text-quality")
    arguments = parser.parse_args()
    destination = arguments.output.resolve()
    if destination == RETAINED or RETAINED in destination.parents:
        raise ValueError("Do not replace historical corpus evidence")
    destination.mkdir(parents=True, exist_ok=True)
    report = {
        "scope": "Host PDFium extraction and Poppler renders; not Android, OCR, production navigation, or universal layout classification.",
        "candidate_meaning": "Passed these bounded geometry checks only; source text correctness and semantic order remain unchecked unless separately observed.",
        "cross_page_policy": "Each source page is assessed separately. Paragraphs never join across pages. Headers and footers remain in physical order; their semantic roles are not inferred or removed.",
        "source_layer_evidence": {name: fingerprint(RETAINED / name) for name in (
            "raven-page9-poppler-layout.txt", "census-page1-poppler-layout.txt")},
        "sources": {},
    }
    manifest = json.loads((ROOT / "corpus-manifest.json").read_text())
    cards = []
    for sample in manifest["samples"]:
        if not sample["filename"].endswith(".pdf"):
            continue
        path = ROOT / "_out/corpus/originals" / sample["filename"]
        verify_input(path, sample)
        blocks = extract_pdf(path)
        metadata = run("pdfinfo", str(path))
        pages = int(re.search(r"Pages:\s+(\d+)", metadata)[1])
        observations = {}
        for page in range(1, pages + 1):
            selected = [block for block in blocks if block["page"] == page - 1]
            errors = RAVEN_ERRORS if sample["id"] == "raven-1873-scan" and page == 9 else ()
            observations[str(page)] = page_observation(path, page, selected, errors)
        report["sources"][sample["id"]] = {"input": fingerprint(path), "pages": observations}
        selected_pages = {"nist-text-pdf": [5], "census-multicolumn-pdf": [1, 2], "raven-1873-scan": [9]}[sample["id"]]
        for page in selected_pages:
            selected = [block for block in blocks if block["page"] == page - 1]
            observation = observations[str(page)]
            prefix = f"{sample['id']}-page{page}"
            source_image = destination / f"{prefix}-original.png"
            render(path, page, source_image)
            (destination / f"{prefix}-raw-geometry.txt").write_text("\n".join(block["text"] for block in selected) + "\n")
            run("pdftotext", "-f", str(page), "-l", str(page), "-layout", str(path), str(destination / f"{prefix}-poppler-layout.txt"))
            observation["rendered_original_preview"] = fingerprint(source_image)
            anchor_text = "NCE" if sample["id"] == "raven-1873-scan" else next(block["text"] for block in selected if len(block["text"]) > 20)
            anchor = anchor_for(path, blocks, anchor_text)
            observation["source_anchor"] = anchor
            observation["source_anchor_resolves"] = resolve_anchor(path, blocks, anchor) == anchor_text
            for width in (360, 720):
                reflow = destination / f"{prefix}-reflow{width}.pdf"
                if observation["view"] != "reflow":
                    reflow.unlink(missing_ok=True)
                    reflow.with_suffix(".png").unlink(missing_ok=True)
                    continue
                lines = reflow_pdf(selected, reflow, width)
                readback = run("pdftotext", "-raw", str(reflow), "-")
                expected = re.sub(r"\s+", "", "".join(paragraph["text"] for paragraph in observation["paragraph_candidates"]))
                actual = re.sub(r"\s+", "", readback)
                observation.setdefault("layout_diagnostics_not_fidelity", {})[str(width)] = {
                    "paragraph_height_derived_lines": lines,
                    "expected_nonspace_characters": len(expected), "readback_nonspace_characters": len(actual),
                    "ordered_nonspace_matches_candidate": actual == expected,
                    "missing_character_counts": dict(Counter(expected) - Counter(actual)),
                    "output_pdf": fingerprint(reflow),
                }
                render(reflow, 1, reflow.with_suffix(".png"))
                cards.append((f"NIST page {page}, width {width} PDF points", "Candidate reflow, not fidelity validation. First generated page only.", reflow.with_suffix(".png").name))
            label = "Candidate reflow available; original remains accessible." if observation["view"] == "reflow" else "Original-page fallback. Extracted text is unreliable."
            cards.append((f"{sample['title']}, source page {page}", label, source_image.name))
            print(f"{sample['id']} page {page}: {observation['status']}; {observation['metrics']}; {len(observation['paragraph_candidates'])} paragraph candidates")
    raster_sample = json.loads((RETAINED / "python-observations.json").read_text())["raven_raster_only_derivative"]
    verify_input(RASTER, raster_sample)
    raster = page_observation(RASTER, 1, extract_pdf(RASTER))
    raster["provenance"] = "Byte-for-byte retained image-only derivative of Raven source page 9; no new recognition or fixture generation. Library of Congress."
    render(RASTER, 1, destination / "raven-raster-only-original.png")
    report["retained_image_only_derivative"] = raster
    cards.append(("Raven page 9, retained image-only derivative", "Original-page fallback. Text is absent, not an extraction-order success.", "raven-raster-only-original.png"))
    report["implementation_files"] = {name: fingerprint(ROOT / name) for name in (
        "proof.py", "pdf_text_quality.py", "corpus_probe.py", "text_quality_probe.py", "test_pdf_text_quality.py")}
    (destination / "observations.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    panels = "".join(f'<article><h2>{escape(title)}</h2><p>{escape(label)}</p><img src="data:image/png;base64,{base64.b64encode((destination / image).read_bytes()).decode()}" alt="{escape(title)}"></article>' for title, label, image in cards)
    (destination / "previews.html").write_text('''<!doctype html><html lang="en"><meta charset="utf-8"><title>Bounded PDF text-quality evidence</title><style>
body{max-width:1100px;margin:24px auto;background:#f7f1e6;color:#392e26;font:16px system-ui}section{display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:16px}article{padding:16px;border:1px solid #c5b8a7;border-radius:12px}h2{font-size:17px}img{width:100%;height:auto}p{line-height:1.5}</style>
<h1>Bounded host evidence, not Android verification</h1><p>Original pages remain complete. Candidate reflow passed bounded geometry checks, not a universal fidelity test. No OCR ran. The first generated reflow page does not show the whole source page; the PDF output retains the rest.</p><section>''' + panels + "</section></html>\n")


if __name__ == "__main__":
    main()
