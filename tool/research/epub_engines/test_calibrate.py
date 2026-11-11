import unittest
from contextlib import chdir
import json
import os
from pathlib import Path
import subprocess
import tempfile
from unittest.mock import patch
import zipfile

from calibrate import has_source_excerpt, main


class SourceEvidenceTest(unittest.TestCase):
    def test_rendered_words_must_include_an_independent_source_excerpt(self):
        source = "Alice was beginning to get very tired of sitting by her sister on the bank."
        self.assertTrue(has_source_excerpt("I: Down the Rabbit-Hole\nAlice was beginning to get very tired of sitting", source))
        self.assertFalse(has_source_excerpt("The renderer reached chapter one and displayed a valid frame", source))
        self.assertFalse(has_source_excerpt("Alice", source))
        self.assertFalse(has_source_excerpt("", source))

    def test_typographic_punctuation_and_whitespace_do_not_hide_matching_words(self):
        source = "She said, ‘Alice was beginning to get very tired of sitting.’"
        self.assertTrue(has_source_excerpt("ALICE was beginning\nto get very tired of sitting", source))

    def test_a_title_only_page_must_show_the_complete_independent_source_heading(self):
        source = 'II The Pool of Tears Curiouser and curiouser! cried Alice.'
        headings = ['II The Pool of Tears']
        self.assertTrue(has_source_excerpt('II\nThe Pool of Tears', source, headings))
        self.assertTrue(has_source_excerpt('THE POOL OF TEARS\nIl', source, headings))
        self.assertFalse(has_source_excerpt('The Pool', source, headings))
        self.assertFalse(has_source_excerpt('III A Caucus-Race', source, headings))
        self.assertFalse(has_source_excerpt('The Pool of Tears', source))

    def test_reference_promotion_requires_successful_workload_assertions(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "model").write_bytes(b"mocked OCR model")
            assets = root / "assets"
            runs = root / "runs"
            assets.mkdir()
            runs.mkdir()
            text = "Alice was beginning to get very tired of sitting by her sister."
            with zipfile.ZipFile(assets / "fixture.epub", "w") as archive:
                archive.writestr("chapter.xhtml", '<html xmlns="http://www.w3.org/1999/xhtml"><body>' + text + '</body></html>')
            book = {"target": {"index": 0}, "file": "fixture.epub",
                    "sections": [{"path": "chapter.xhtml"}, {"path": "chapter.xhtml"}]}
            (assets / "manifest.json").write_text(json.dumps({"books": {name: book for name in ("prose", "long", "illustrated")}}))
            reviews = {}
            directories = []
            for engine in ("bookfin", "webview", "koreader"):
                for name in ("prose", "long", "illustrated"):
                    run = f"calibration-{engine}-{name}"
                    directory = runs / run
                    directory.mkdir()
                    directories.append(directory)
                    for sequence, case in enumerate(("target18", "target20", "turn1", "turn2", "turn3", "before_crossing18", "after_crossing18")):
                        row = {"engine": engine, "book": name, "case": case, "run_id": run,
                               "visible_text": text, "capture_sha256": "a" * 64, "warmup": True, "round": -1}
                        (directory / f"{sequence}.json").write_text(json.dumps(row))
                        (directory / f"{sequence}.png").write_bytes(b"mocked OCR input")
                        reviews[f"{engine}/{name}/{case}"] = {"capture_sha256": "a" * 64}
            (root / "reviews.json").write_text(json.dumps(reviews))
            arguments = ["calibrate.py", str(runs), "--assets", str(assets), "--output", str(root / "references.json"),
                         "--image-reviews", str(root / "reviews.json")]
            with chdir(root), patch.dict(os.environ, {"BOOKFIN_NIX_SHELL": "1", "BOOKFIN_OCR_MODEL": str(root / "model")}), \
                    patch("sys.argv", arguments), patch("calibrate.subprocess.run", return_value=subprocess.CompletedProcess([], 0, text, "")):
                with self.assertRaisesRegex(RuntimeError, "workload assertions"):
                    main()
                for directory in directories:
                    (directory / "DONE").touch()
                    (runs / (directory.name + "-instrumentation.txt")).write_text("OK (1 test)")
                main()
                self.assertEqual(len(json.loads((root / "references.json").read_text())), 63)
