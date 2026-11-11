"""Remove timed-run PNG copies whose pixels equal a committed reference PNG."""
import hashlib, json, sys
from pathlib import Path

root = Path("tool/research/epub_engines/evidence")
sets = {"calibration-swiftshader": root / "references.json", "measured-swiftshader": root / "references.json",
        "measured-gpu": root / "symmetric-20261111/references-gpu.json",
        "measured-drawn-gpu": root / "symmetric-20261111/references-gpu.json"}
lines = ["# PNG copies removed because their pixel SHA-256 equals a reference whose PNG is committed",
         "# path\tpng_file_sha256\tcapture_sha256\treference_key\treference_png"]
removed = 0
for name, reference_file in sets.items():
    references = json.loads(reference_file.read_text())
    for png in sorted((root / "symmetric-20261111" / name).glob("*/*.png")):
        row = json.loads(png.with_suffix(".json").read_text())
        key = f"{row['engine']}/{row['book']}/{row['case']}"
        reference = references[key]
        if row["capture_sha256"] != reference["capture_sha256"]:
            sys.exit(f"{png}: pixels differ from {key}; not a duplicate")
        if not Path(reference["png_path"]).is_file():
            sys.exit(f"{png}: reference PNG {reference['png_path']} is missing")
        lines.append("\t".join((str(png), hashlib.sha256(png.read_bytes()).hexdigest(), row["capture_sha256"], key, reference["png_path"])))
        png.unlink()
        removed += 1
(root / "symmetric-20261111/png-duplicates-removed.tsv").write_text("\n".join(lines) + "\n")
print(removed, "duplicate PNG copies removed")
