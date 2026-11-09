"""Tests of fetch_epub_corpus.py. Run: python3 -I tool/reader/test_fetch_epub_corpus.py"""

import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fetch_epub_corpus as corpus

BOOK = b"PK book bytes"


def entry(**changes):
    book = {
        "id": "se-test",
        "title": "Test",
        "source": "standard-ebooks",
        "url": "https://standardebooks.org/ebooks/a/b/downloads/a_b.epub",
        "sha256": hashlib.sha256(BOOK).hexdigest(),
        "bytes": len(BOOK),
        "format": "epub",
        "why": "test",
    }
    book.update(changes)
    return book


class Server:
    """A download that writes [content] and records each request."""

    def __init__(self, content=BOOK):
        self.content = content
        self.requests = []

    def __call__(self, url, output, limit):
        self.requests.append((url, limit))
        Path(output).write_bytes(self.content)


class FetchTest(unittest.TestCase):
    def setUp(self):
        self.directory = Path(tempfile.mkdtemp())
        self.pauses = []

    def run_corpus(self, books, server, pin=False):
        listing = self.directory / "list.json"
        listing.write_text(json.dumps({"books": books}))
        failures = corpus.fetch_all(
            listing, self.directory / "books", server, self.pauses.append, pin=pin
        )
        return failures, json.loads(listing.read_text())["books"]

    def test_a_download_with_the_pinned_digest_is_kept(self):
        failures, _ = self.run_corpus([entry()], Server())
        self.assertEqual(failures, [])
        self.assertEqual((self.directory / "books/se-test.epub").read_bytes(), BOOK)

    def test_a_download_with_another_digest_is_refused_and_leaves_no_file(self):
        failures, _ = self.run_corpus([entry()], Server(b"changed"))
        self.assertEqual(len(failures), 1)
        self.assertIn("se-test", failures[0])
        self.assertEqual(list((self.directory / "books").iterdir()), [])

    def test_a_present_book_is_checked_and_not_downloaded_again(self):
        (self.directory / "books").mkdir()
        (self.directory / "books/se-test.epub").write_bytes(BOOK)
        server = Server()
        failures, _ = self.run_corpus([entry()], server)
        self.assertEqual(failures, [])
        self.assertEqual(server.requests, [])

    def test_a_present_book_with_another_digest_is_a_failure(self):
        (self.directory / "books").mkdir()
        (self.directory / "books/se-test.epub").write_bytes(b"changed")
        failures, _ = self.run_corpus([entry()], Server())
        self.assertEqual(len(failures), 1)

    def test_downloads_run_one_at_a_time_with_a_pause_after_each(self):
        books = [entry(id="a"), entry(id="b"), entry(id="c")]
        server = Server()
        self.run_corpus(books, server)
        self.assertEqual(len(server.requests), 3)
        self.assertEqual(self.pauses, [corpus.PAUSE_SECONDS] * 3)

    def test_a_download_is_limited_to_the_pinned_size(self):
        server = Server()
        self.run_corpus([entry()], server)
        self.assertEqual(server.requests[0][1], len(BOOK))

    def test_a_book_that_the_tests_make_is_not_downloaded(self):
        server = Server()
        failures, _ = self.run_corpus(
            [entry(source="bookfin-showcase", url=None)], server
        )
        self.assertEqual(failures, [])
        self.assertEqual(server.requests, [])

    def test_pin_records_the_digest_and_size_of_an_unpinned_book(self):
        server = Server()
        failures, books = self.run_corpus(
            [entry(sha256=None, bytes=None)], server, pin=True
        )
        self.assertEqual(failures, [])
        self.assertEqual(server.requests[0][1], corpus.MAX_BYTES)
        self.assertEqual(books[0]["sha256"], hashlib.sha256(BOOK).hexdigest())
        self.assertEqual(books[0]["bytes"], len(BOOK))

    def test_an_unpinned_book_is_a_failure_without_pin(self):
        server = Server()
        failures, books = self.run_corpus([entry(sha256=None, bytes=None)], server)
        self.assertEqual(len(failures), 1)
        self.assertEqual(server.requests, [])
        self.assertIsNone(books[0]["sha256"])

    def test_pin_keeps_a_pinned_digest(self):
        failures, books = self.run_corpus([entry()], Server(b"changed"), pin=True)
        self.assertEqual(len(failures), 1)
        self.assertEqual(books[0]["sha256"], hashlib.sha256(BOOK).hexdigest())

    def test_a_failed_download_leaves_no_file_and_the_run_goes_on(self):
        def broken(url, output, limit):
            Path(output).write_bytes(b"half")
            raise OSError("connection reset")

        listing = self.directory / "list.json"
        listing.write_text(json.dumps({"books": [entry(id="a"), entry(id="b")]}))
        failures = corpus.fetch_all(
            listing, self.directory / "books", broken, self.pauses.append
        )
        self.assertEqual(len(failures), 2)
        self.assertEqual(list((self.directory / "books").iterdir()), [])
        self.assertEqual(len(self.pauses), 2)


if __name__ == "__main__":
    unittest.main()
