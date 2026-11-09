"""Download the EPUB corpus of tool/reader/epub_corpus.json.

Run it in the dev shell from the repository root:

    python3 -I tool/reader/fetch_epub_corpus.py [--pin]

It downloads each book that is not present into .cache/epub-corpus/books,
one file at a time with a pause after each, and checks the size and SHA-256
of every book against the list. With --pin, it records the size and SHA-256
of each book that the list does not pin yet. A book without a URL is made
by the tests (tool/showcase_media.dart), so the script skips it.
"""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import time

# The pause after each download, so that the run asks Standard Ebooks and
# Project Gutenberg for one file every few seconds at most.
PAUSE_SECONDS = 3

# Publication.maxArchiveBytes: Bookfin admits no larger book.
MAX_BYTES = 64 * 1024 * 1024


def digest(path):
    with Path(path).open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def check(path, book):
    """Raise ValueError unless [path] has the size and SHA-256 that [book] pins."""
    size = Path(path).stat().st_size
    if size != book["bytes"]:
        raise ValueError(f"{book['id']}: {size} bytes, the list pins {book['bytes']}")
    found = digest(path)
    if found != book["sha256"]:
        raise ValueError(f"{book['id']}: SHA-256 {found}, the list pins {book['sha256']}")


def curl(url, output, limit):
    subprocess.run([
        "curl", "--fail", "--location", "--silent", "--show-error",
        "--proto", "=https", "--proto-redir", "=https",
        "--connect-timeout", "15", "--max-time", "300",
        "--max-filesize", str(limit),
        "--user-agent", "Bookfin corpus test (one file at a time)",
        url, "--output", str(output),
    ], check=True, timeout=310)


def fetch(book, directory, download, pin):
    """Make sure that [book] is in [directory] with its pinned size and SHA-256."""
    if book["url"] is None:
        return
    pinned = book["sha256"] is not None
    if not pinned and not pin:
        raise ValueError(f"{book['id']}: the list pins no SHA-256; run with --pin")
    path = directory / f"{book['id']}.{book['format']}"
    if not path.exists():
        partial = path.with_name(path.name + ".partial")
        try:
            download(book["url"], partial, book["bytes"] if pinned else MAX_BYTES)
            if not pinned:
                book["sha256"] = digest(partial)
                book["bytes"] = partial.stat().st_size
            check(partial, book)
            partial.replace(path)
        finally:
            partial.unlink(missing_ok=True)
    elif not pinned:
        book["sha256"] = digest(path)
        book["bytes"] = path.stat().st_size
    check(path, book)


def fetch_all(listing, directory, download, pause, pin=False):
    """Fetch every book of the list at [listing] into [directory].

    Returns one message for each book that failed. With [pin], writes the
    sizes and SHA-256 values that it recorded back to the list.
    """
    books = json.loads(Path(listing).read_text())["books"]
    directory.mkdir(parents=True, exist_ok=True)
    failures = []
    requests = []

    def counted(url, output, limit):
        requests.append(url)
        download(url, output, limit)

    for book in books:
        asked = len(requests)
        try:
            fetch(book, directory, counted, pin)
            print(f"ok {book['id']}")
        except (OSError, ValueError, subprocess.SubprocessError) as error:
            failures.append(f"{book['id']}: {error}")
            print(f"FAILED {failures[-1]}", file=sys.stderr)
        if len(requests) > asked:
            pause(PAUSE_SECONDS)
    if pin:
        Path(listing).write_text(
            json.dumps({"books": books}, indent=2, ensure_ascii=False) + "\n"
        )
    return failures


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pin", action="store_true")
    arguments = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    failures = fetch_all(
        root / "tool/reader/epub_corpus.json",
        root / ".cache/epub-corpus/books",
        curl,
        time.sleep,
        pin=arguments.pin,
    )
    if failures:
        sys.exit(f"{len(failures)} books failed")


if __name__ == "__main__":
    main()
