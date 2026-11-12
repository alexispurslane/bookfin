"""Remove PNG copies whose pixels equal a committed host-GPU reference PNG; list each one, keep the rest."""
import hashlib, json
from pathlib import Path

root = Path("tool/research/epub_engines/evidence/rerun-20261112")
references = json.loads(Path("tool/research/epub_engines/evidence/symmetric-20261111/references-gpu.json").read_text())
lines, kept = [], []
for png in sorted(root.glob("**/*.png")):
    row = json.loads(png.with_suffix(".json").read_text())
    key = f"{row['engine']}/{row['book']}/{row['case']}"
    reference = references[key]
    if row["capture_sha256"] != reference["capture_sha256"] or not Path(reference["png_path"]).is_file():
        kept.append(f"{png}\t{row['capture_sha256']}\t{key}")
        continue
    lines.append("\t".join((str(png), hashlib.sha256(png.read_bytes()).hexdigest(), row["capture_sha256"], key, reference["png_path"])))
    png.unlink()
(root / "png-duplicates-removed.tsv").write_text("".join(line + "\n" for line in lines))
(root / "png-kept-not-reference.tsv").write_text("# PNG copies kept because their pixels differ from the host-GPU reference\n" + "".join(k + "\n" for k in kept))
print(len(lines), "removed;", len(kept), "kept")
