import hashlib
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

from package import assemble, write_archive


class InstallablePackage(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.dll = b"synthetic assembly bytes"
        self.sources = {"plugin/Plugin.cs": b"synthetic source"}
        self.runtime = {"testedServerVersion": "12.4.0", "sdk": "10.0.401"}

    def package(self):
        return assemble(self.dll, self.sources, self.runtime)

    def test_an_install_contains_the_assembly_and_matching_jellyfin_identity(self):
        contents = self.package()
        self.assertEqual(set(contents), {"Bookfin.Storage.dll", "meta.json", "manifest.json"})
        metadata = json.loads(contents["meta.json"])
        self.assertEqual(metadata["guid"], "55fb5a92-7fbd-411c-9838-6ee4c88d168b")
        self.assertEqual(metadata["version"], "0.1.1.0")
        self.assertEqual(metadata["name"], "Bookfin Storage")

    def test_the_manifest_identifies_every_source_byte_and_the_installed_assembly(self):
        contents = self.package()
        self.assertIn("manifest.json", contents, "Installable bytes need an exact source and binary manifest")
        manifest = json.loads(contents["manifest.json"])
        self.assertEqual(manifest["sourceSha256"], {
            name: hashlib.sha256(contents).hexdigest() for name, contents in self.sources.items()
        })
        self.assertEqual(manifest["filesSha256"]["Bookfin.Storage.dll"], hashlib.sha256(self.dll).hexdigest())
        self.assertEqual(manifest["runtime"], self.runtime)
        self.assertEqual(manifest["api"], "/BookfinStorage/v1/objects")
        self.assertEqual(manifest["database"], "bookfin-storage-v1.sqlite")

    def test_archives_are_identical_despite_input_order_and_host_timestamps(self):
        first = self.root / "first.zip"
        second = self.root / "second.zip"
        contents = {"meta.json": b"{}", "Bookfin.Storage.dll": self.dll}
        write_archive(first, contents)
        write_archive(second, dict(reversed(list(contents.items()))))
        self.assertEqual(first.read_bytes(), second.read_bytes())
        with zipfile.ZipFile(first) as archive:
            self.assertEqual(archive.namelist(), sorted(contents))
            self.assertTrue(all(entry.date_time == (1980, 1, 1, 0, 0, 0) for entry in archive.infolist()))
            self.assertEqual(archive.read("Bookfin.Storage.dll"), self.dll)


if __name__ == "__main__":
    unittest.main()
