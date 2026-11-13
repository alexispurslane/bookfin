from pathlib import Path
import tempfile
import unittest
import zipfile

from prepare import copy_tree, describe


class CorpusDescriptionTest(unittest.TestCase):
    def test_repeated_preparation_replaces_read_only_nix_source_copies(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "source"
            target = Path(directory) / "target"
            source.mkdir()
            original = source / "asset.js"
            original.write_text("first version")
            original.chmod(0o444)
            copy_tree(source, target)
            original.chmod(0o644)
            original.write_text("second version")
            original.chmod(0o444)
            copy_tree(source, target)
            self.assertEqual((target / "asset.js").read_text(), "second version")

    def test_keeps_the_spine_order_images_and_navigation_title_of_the_requested_section(self):
        with tempfile.TemporaryDirectory() as directory:
            book = Path(directory) / "book.epub"
            # Fixture identity depends on content, not the time of this run.
            entry_time = (2026, 11, 1, 0, 0, 0)
            with zipfile.ZipFile(book, "w") as archive:
                archive.writestr(zipfile.ZipInfo("META-INF/container.xml", entry_time), '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="EPUB/package.opf"/></rootfiles></container>')
                archive.writestr(zipfile.ZipInfo("EPUB/package.opf", entry_time), '<package xmlns="http://www.idpf.org/2007/opf"><manifest><item id="first" href="first.xhtml"/><item id="second" href="second.xhtml"/><item id="nav" href="nav.xhtml" properties="nav"/></manifest><spine><itemref idref="second"/><itemref idref="first"/></spine></package>')
                archive.writestr(zipfile.ZipInfo("EPUB/first.xhtml", entry_time), '<html xmlns="http://www.w3.org/1999/xhtml"><body><h1>I</h1><p>The first story.</p><img src="picture.jpg"/></body></html>')
                archive.writestr(zipfile.ZipInfo("EPUB/second.xhtml", entry_time), '<html xmlns="http://www.w3.org/1999/xhtml"><body><h1>II</h1><p>The second story.</p></body></html>')
                archive.writestr(zipfile.ZipInfo("EPUB/nav.xhtml", entry_time), '<html xmlns="http://www.w3.org/1999/xhtml"><body><nav><a href="first.xhtml#chapter">One: The beginning</a><a href="second.xhtml">Two</a></nav></body></html>')
            sections = describe(book)
            self.assertEqual([section["path"] for section in sections], ["EPUB/second.xhtml", "EPUB/first.xhtml"])
            self.assertEqual([section["images"] for section in sections], [0, 1])
            self.assertEqual(sections[1]["heading"], "I")
            self.assertEqual(sections[1].get("toc_title"), "One: The beginning")


if __name__ == "__main__":
    unittest.main()
