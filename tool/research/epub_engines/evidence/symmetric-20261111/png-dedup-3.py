"""Remove PNG copies whose pixels equal a committed host-GPU reference PNG; append each to the list, keep the rest."""
import hashlib, json
from pathlib import Path

root = Path("tool/research/epub_engines/evidence/symmetric-20261111")
references = json.loads((root / "references-gpu.json").read_text())
listing = root / "png-duplicates-removed.tsv"
lines, kept = [], []
for name in ("measured-drawn4-gpu",):
    for png in sorted((root / name).glob("**/*.png")):
        row = json.loads(png.with_suffix(".json").read_text())
        key = f"{row['engine']}/{row['book']}/{row['case']}"
        reference = references[key]
        if row["capture_sha256"] != reference["capture_sha256"] or not Path(reference["png_path"]).is_file():
            kept.append(f"{png}\t{row['capture_sha256']}\t{key}")
            continue
        lines.append("\t".join((str(png), hashlib.sha256(png.read_bytes()).hexdigest(), row["capture_sha256"], key, reference["png_path"])))
        png.unlink()
with listing.open("a") as out:
    out.write("".join(line + "\n" for line in lines))
(root / "png-kept-not-reference-drawn4.tsv").write_text("# PNG copies kept because their pixels differ from the host-GPU reference\n" + "".join(k + "\n" for k in kept))
print(len(lines), "removed;", len(kept), "kept")
