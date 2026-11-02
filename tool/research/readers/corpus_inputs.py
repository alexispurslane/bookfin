"""Bounded, fingerprinted public-corpus acquisition for host research only."""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess


def verify_input(path, sample):
    """Require the manifest's exact byte count and SHA-256 within 16 MB."""
    if not 0 < sample["size_bytes"] <= 16_000_000:
        raise ValueError("Source must fit the 16 MB download limit")
    if Path(path).stat().st_size != sample["size_bytes"]:
        raise ValueError(f"Source byte count differs: {path}")
    with Path(path).open("rb") as source:
        if hashlib.file_digest(source, "sha256").hexdigest() != sample["sha256"]:
            raise ValueError(f"Source SHA-256 differs: {path}")


def publish_input(candidate, destination, sample):
    """Publish a verified download without changing originals on rejection."""
    verify_input(candidate, sample)
    Path(candidate).replace(destination)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verify-only", action="store_true")
    arguments = parser.parse_args()
    root = Path(__file__).resolve().parent
    samples = json.loads((root / "corpus-manifest.json").read_text())["samples"]
    if len(samples) > 10 or sum(sample["size_bytes"] for sample in samples) > 32_000_000:
        raise ValueError("Corpus exceeds 10 sources or 32 MB total")
    originals = root / "_out/corpus/originals"
    originals.mkdir(parents=True, exist_ok=True)
    for sample in samples:
        destination = originals / sample["filename"]
        if destination.exists() or arguments.verify_only:
            verify_input(destination, sample)
        else:
            candidate = destination.with_suffix(destination.suffix + ".partial")
            try:
                subprocess.run([
                    "curl", "--fail", "--location", "--silent", "--show-error",
                    "--proto", "=https", "--proto-redir", "=https",
                    "--connect-timeout", "15", "--max-time", "90",
                    "--max-filesize", str(sample["size_bytes"]),
                    sample["url"], "--output", str(candidate),
                ], check=True, timeout=95)
                publish_input(candidate, destination, sample)
            finally:
                candidate.unlink(missing_ok=True)
        print(f"verified {sample['id']}: {sample['size_bytes']} bytes {sample['sha256']}")


if __name__ == "__main__":
    main()
