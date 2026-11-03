"""Acquire only pinned PDF inputs into a new production-integration cache."""

import json
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(root / "tool/research/readers"))
from corpus_inputs import verify_input

destination = root / ".cache/reader-corpus"
destination.mkdir(parents=True, exist_ok=True)
manifest = json.loads((root / "tool/research/readers/corpus-manifest.json").read_text())
for sample in manifest["samples"]:
    if not sample["format"].startswith("pdf"):
        continue
    path = destination / sample["filename"]
    if not path.exists():
        partial = path.with_suffix(".partial")
        try:
            subprocess.run([
                "curl", "--fail", "--location", "--silent", "--show-error",
                "--proto", "=https", "--proto-redir", "=https",
                "--max-time", "90", "--max-filesize", str(sample["size_bytes"]),
                sample["url"], "--output", str(partial),
            ], check=True, timeout=95)
            verify_input(partial, sample)
            partial.replace(path)
        finally:
            partial.unlink(missing_ok=True)
    verify_input(path, sample)
    print(f"verified {sample['filename']}: {sample['sha256']}")
