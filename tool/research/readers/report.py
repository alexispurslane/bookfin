"""Save bounded, inspectable observations from real fixture runs."""

import hashlib
import importlib.metadata
import json
from pathlib import Path
import subprocess
import zipfile

import markdown
from PIL import Image

from fixtures import FIXTURES
from proof import anchor_for, extract_pdf, reflow_pdf, safe_html


def report():
    output = Path("_out")
    simple = extract_pdf(FIXTURES / "simple.pdf")
    phone_lines = reflow_pdf(simple, output / "reflow-360.pdf", 360)
    wide_lines = reflow_pdf(simple, output / "reflow-720.pdf", 720)
    for name in ("simple", "columns", "scanned"):
        subprocess.run(["pdftoppm", "-singlefile", "-scale-to", "720", "-png", str(FIXTURES / f"{name}.pdf"), str(output / f"{name}-original")], check=True, capture_output=True)
    subprocess.run(["pdftoppm", "-singlefile", "-scale-to-x", "360", "-scale-to-y", "-1", "-png", str(output / "reflow-360.pdf"), str(output / "reflow-360")], check=True, capture_output=True)
    Image.open(output / "scanned-original.ppm").save(output / "scanned-pdfium.png")
    html = safe_html((FIXTURES / "chapter.html").read_text(), FIXTURES)
    (output / "passive.html").write_text(html)
    (output / "markdown-passive.html").write_text(safe_html(markdown.markdown((FIXTURES / "chapter.md").read_text(), extensions=["fenced_code"]), FIXTURES))
    observations = {
        "fixtures": {path.name: {"bytes": path.stat().st_size, "sha256": hashlib.sha256(path.read_bytes()).hexdigest()} for path in sorted(FIXTURES.iterdir()) if path.is_file() and path.name != "README.md"},
        "python_packages": {name: importlib.metadata.version(name) for name in ("reportlab", "pillow", "markdown", "bleach", "lxml")},
        "pdfium_version": (output / "pdfium-host/VERSION").read_text().strip(),
        "reflow": {"font_size_pdf_points": 18, "width_pdf_points": 360, "content_width_pdf_points": 328, "phone_lines": phone_lines, "wide_720_lines": wide_lines, "source_anchor": anchor_for(FIXTURES / "simple.pdf", simple, "old road")},
        "column_reflow": [block["text"] for block in extract_pdf(FIXTURES / "columns.pdf")],
        "column_poppler_default": subprocess.run(["pdftotext", str(FIXTURES / "columns.pdf"), "-"], capture_output=True, text=True, check=True).stdout.splitlines(),
        "table_reflow_known_failure": [block["text"] for block in extract_pdf(FIXTURES / "table.pdf")],
        "scan_extracted_blocks": len(extract_pdf(FIXTURES / "scanned.pdf")),
        "headings": [block["text"] for block in simple if block["heading"]],
        "converted_epubs": {},
    }
    for name in ("mobi6-plain", "mobi6-palmdoc", "alice"):
        with zipfile.ZipFile(output / f"{name}.epub") as archive:
            observations["converted_epubs"][name] = {"entries": len(archive.namelist()), "bytes": (output / f"{name}.epub").stat().st_size}
    apk = output / "flutter-smoke/build/app/outputs/flutter-apk/app-debug.apk"
    if apk.exists():
        with zipfile.ZipFile(apk) as archive:
            observations["android_apk"] = {
                "bytes": apk.stat().st_size,
                "sha256": hashlib.file_digest(apk.open("rb"), "sha256").hexdigest(),
                "native_entries": {entry.filename: entry.file_size for entry in archive.infolist() if entry.filename.startswith("lib/")},
            }
            comparisons = {}
            for name, reference in {
                "libpdfium.so": output / "pdfium-android/lib/libpdfium.so",
                "libmobi.so": output / "android-arm64/src/libmobi.so",
                "libreader_convert.so": output / "libreader_convert.so",
            }.items():
                packaged = hashlib.sha256(archive.read(f"lib/arm64-v8a/{name}")).hexdigest()
                pinned = hashlib.sha256(reference.read_bytes()).hexdigest()
                if packaged != pinned:
                    raise ValueError("Packaged engine differs from the pinned native proof")
                comparisons[name] = {"sha256": packaged, "matches_pinned_native_proof": True}
            observations["android_apk"]["engine_provenance"] = comparisons
    (output / "report.json").write_text(json.dumps(observations, indent=2) + "\n")
    print(json.dumps({"reflow": observations["reflow"], "scan_extracted_blocks": observations["scan_extracted_blocks"], "table_reflow_known_failure": observations["table_reflow_known_failure"]}, indent=2))


if __name__ == "__main__":
    report()
