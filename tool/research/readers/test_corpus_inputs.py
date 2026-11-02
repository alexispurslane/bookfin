"""Acquisition must reject changed bytes before replacing a retained original."""

from pathlib import Path
import tempfile
import unittest

from corpus_inputs import publish_input, verify_input


class CorpusInputs(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.candidate = self.root / "candidate"
        self.candidate.write_bytes(b"abc")
        self.sample = {
            "size_bytes": 3,
            "sha256": "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
        }

    def test_accepts_the_exact_recorded_source_bytes(self):
        verify_input(self.candidate, self.sample)
        self.assertEqual(self.candidate.read_bytes(), b"abc")

    def test_rejects_changed_bytes_even_when_the_length_matches(self):
        self.candidate.write_bytes(b"abd")
        with self.assertRaisesRegex(ValueError, "SHA-256"):
            verify_input(self.candidate, self.sample)

    def test_rejects_an_incomplete_download(self):
        self.candidate.write_bytes(b"ab")
        with self.assertRaisesRegex(ValueError, "byte count"):
            verify_input(self.candidate, self.sample)

    def test_rejects_manifest_entries_above_the_download_limit(self):
        with self.assertRaisesRegex(ValueError, "16 MB"):
            verify_input(self.candidate, dict(self.sample, size_bytes=16_000_001))

    def test_rejection_preserves_a_retained_original(self):
        destination = self.root / "original"
        destination.write_bytes(b"retained")
        self.candidate.write_bytes(b"abd")
        with self.assertRaises(ValueError):
            publish_input(self.candidate, destination, self.sample)
        self.assertEqual(destination.read_bytes(), b"retained")

    def test_verified_download_moves_into_its_final_name(self):
        destination = self.root / "original"
        publish_input(self.candidate, destination, self.sample)
        self.assertEqual(destination.read_bytes(), b"abc")
        self.assertFalse(self.candidate.exists())


if __name__ == "__main__":
    unittest.main()
