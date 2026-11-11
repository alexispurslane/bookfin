import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import unicodedata
import xml.etree.ElementTree as ElementTree
import zipfile


def words(text):
    return re.findall(r"[a-z0-9]+", unicodedata.normalize("NFKD", text).lower())


def has_source_excerpt(rendered, source, headings=()):
    shown = words(rendered)
    original = " " + " ".join(words(source)) + " "
    if any(" " + " ".join(shown[index:index+8]) + " " in original
           for index in range(len(shown)-7)):
        return True
    for heading in headings:
        title = words(heading)
        if title and re.fullmatch(r"[ivxlcdm]+", title[0]):
            title = title[1:]
        if len(title) >= 3 and len(shown) <= len(title) + 2 and " " + " ".join(title) + " " in " " + " ".join(shown) + " ":
            return True
    return False


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("calibration", type=Path)
    parser.add_argument("--assets", type=Path, default=Path(".cache/epub-engines/assets"))
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--image-reviews", type=Path)
    parser.add_argument("--draft", action="store_true")
    args = parser.parse_args()
    if os.environ.get("BOOKFIN_NIX_SHELL") != "1":
        raise RuntimeError("Run through the project Nix dev shell")
    manifest = json.loads((args.assets / "manifest.json").read_text())
    reviews = json.loads(args.image_reviews.read_text()) if args.image_reviews else {}
    model = Path(".cache/epub-engines/tessdata")
    model.mkdir(parents=True, exist_ok=True)
    if not (model / "eng.traineddata").exists():
        (model / "eng.traineddata").symlink_to(os.environ["BOOKFIN_OCR_MODEL"])
    references = {}
    failures = []
    checked_jobs = set()
    for path in sorted(args.calibration.glob("*/[0-9]*.json")):
        if path.parent not in checked_jobs:
            assertion_log = args.calibration / (path.parent.name + "-instrumentation.txt")
            if not (path.parent / "DONE").is_file() or not assertion_log.is_file() or "OK (1 test)" not in assertion_log.read_text():
                raise RuntimeError(f"Reference workload assertions did not pass: {path.parent.name}")
            checked_jobs.add(path.parent)
        row = json.loads(path.read_text())
        if not row["run_id"].startswith("calibration-") or row.get("warmup") is not True or row.get("round") != -1:
            raise RuntimeError("Only separate, excluded calibration workloads can supply references")
        key = "/".join(row[field] for field in ("engine", "book", "case"))
        if key in references:
            if references[key]["capture_sha256"] != row["capture_sha256"]:
                failures.append(f"Unstable calibration pixels: {key} ({path})")
            continue
        book = manifest["books"][row["book"]]
        section = book["target"]["index"] + (row["case"] == "after_crossing18")
        with zipfile.ZipFile(args.assets / book["file"]) as archive:
            document = ElementTree.fromstring(archive.read(book["sections"][section]["path"]))
            body = next(element for element in document.iter() if element.tag.endswith("}body"))
            source = " ".join(body.itertext())
            headings = [" ".join(element.itertext()) for element in body.iter()
                        if element.tag.rsplit("}", 1)[-1] in ("h1", "h2", "h3", "hgroup")]
        picture = path.with_suffix(".png")
        ocr = subprocess.run(["tesseract", str(picture), "stdout", "--tessdata-dir", str(model), "-l", "eng", "--psm", "3"],
                             text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
        path.with_suffix(".ocr.txt").write_text(ocr.stdout)
        source_validated = has_source_excerpt(row["visible_text"], source, headings)
        ocr_validated = has_source_excerpt(ocr.stdout, source, headings)
        image_reviewed = row["book"] != "illustrated" or reviews.get(key, {}).get("capture_sha256") == row["capture_sha256"]
        entry = {**row, "source_section": section, "source_path": book["sections"][section]["path"],
                 "source_validated": source_validated, "ocr_validated": ocr_validated,
                 "ocr_text": ocr.stdout, "image_reviewed": image_reviewed,
                 "image_review": reviews.get(key), "png_path": str(picture),
                 "png_sha256": hashlib.sha256(picture.read_bytes()).hexdigest()}
        references[key] = entry
        if not source_validated or not ocr_validated or not image_reviewed:
            failures.append(f"Incomplete independent content evidence: {key}; source={source_validated}, OCR={ocr_validated}, images={image_reviewed}")
    if len(references) != 63:
        failures.append(f"Expected 63 engine/book/page references, found {len(references)}")
    if failures:
        print("\n".join(failures))
        if not args.draft:
            raise RuntimeError("Reference promotion refused; inspect and resolve calibration evidence")
    args.output.write_text(json.dumps(references, indent=2) + "\n")


if __name__ == "__main__":
    main()
