"""Ticket-only diagnostic: real writers, controlled ZIP clock, no servers/audio."""
from contextlib import ExitStack
import hashlib
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parents[4]
sys.path[:0] = [str(ROOT / "tool/research/epub_engines"), str(ROOT / "tool/research/sync")]
import fixture
from test_prepare import CorpusDescriptionTest
from test_calibrate import ReferencePromotionTest

TIMES = [(2026, 1, 1, 12, 0, 0, 3, 1, -1), (2026, 1, 1, 12, 0, 2, 3, 1, -1)]
OBSERVATIONS = []


def build(owner, clock, changed=False):
    captures = []
    close = zipfile.ZipFile.close
    write = zipfile.ZipFile.writestr
    edits = []

    def capture(archive):
        filename = archive.filename if archive.mode == "w" and archive.fp else None
        close(archive)
        if filename and str(filename).endswith(".epub"):
            captures.append(Path(filename).read_bytes())

    def write_content(archive, name, content, *args, **kwargs):
        # Change only an existing payload at the encoder boundary. All actual
        # owner code and the real encoder run; no second builder is substituted.
        before, after = {
            "prepare": ("The first story.", "The other story."),
            "calibrate": ("Alice was beginning", "Alice was returning"),
            "sync": ("Disposable research.", "Repeatable research."),
        }[owner]
        if changed and before in content:
            content = content.replace(before, after)
            edits.append(name.filename if isinstance(name, zipfile.ZipInfo) else name)
        return write(archive, name, content, *args, **kwargs)

    with ExitStack() as stack:
        stack.enter_context(patch.dict(os.environ))
        os.environ.pop("SOURCE_DATE_EPOCH", None)
        stack.enter_context(patch("zipfile.time.localtime", return_value=clock))
        stack.enter_context(patch.object(zipfile.ZipFile, "close", capture))
        stack.enter_context(patch.object(zipfile.ZipFile, "writestr", write_content))
        if owner == "prepare":
            case = CorpusDescriptionTest("test_keeps_the_spine_order_images_and_navigation_title_of_the_requested_section")
            case.test_keeps_the_spine_order_images_and_navigation_title_of_the_requested_section()
        elif owner == "calibrate":
            case = ReferencePromotionTest("test_reference_promotion_requires_successful_workload_assertions")
            try:
                case.setUp()
            finally:
                case.doCleanups()
        else:
            directory = stack.enter_context(tempfile.TemporaryDirectory())
            root = Path(directory)
            # These existing audio paths bypass ffmpeg. Only ffprobe's unrelated
            # chapter result is stubbed; seed_media's complete EPUB writer runs.
            for relative in ["public/Work/Recording A/z-first", "public/Work/Recording A/a-second",
                             "public/Work/Recording A/m-third", "public/Work/Recording B/other-narrator",
                             "private/Hidden/secret-synthetic"]:
                path = root / "media" / (relative + ".m4b")
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b"unused audio")
            stack.enter_context(patch.object(fixture, "ROOT", root))
            stack.enter_context(patch.object(fixture.subprocess, "check_output", return_value=b'{"chapters":[{}]}'))
            stack.enter_context(patch.object(fixture.subprocess, "run", side_effect=AssertionError("No audio command permitted")))
            fixture.seed_media()
    assert len(captures) == 1, len(captures)
    assert len(edits) == (1 if changed else 0), edits
    data = captures[0]
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        entries = [{"name": entry.filename, "time": entry.date_time,
                    "payloadSha256": hashlib.sha256(archive.read(entry)).hexdigest(),
                    "compression": entry.compress_type, "externalAttributes": entry.external_attr}
                   for entry in archive.infolist()]
    OBSERVATIONS.append({"owner": owner, "clock": clock[:6], "changed": changed,
                         "sha256": hashlib.sha256(data).hexdigest(), "entries": entries})
    return data


class ArchiveTimes(unittest.TestCase):
    def test_clock_control_changes_unfixed_archive_bytes(self):
        archives = []
        for clock in TIMES:
            stream = io.BytesIO()
            with patch.dict(os.environ), patch("zipfile.time.localtime", return_value=clock):
                os.environ.pop("SOURCE_DATE_EPOCH", None)
                with zipfile.ZipFile(stream, "w") as archive:
                    archive.writestr("control.txt", "unchanged")
            archives.append(stream.getvalue())
        self.assertNotEqual(archives[0], archives[1])


def stable(owner):
    def test(self):
        first, second = [build(owner, clock) for clock in TIMES]
        self.assertTrue(first == second, f"{owner}: same payload has distinct archive bytes at the two clocks")
    return test


def sensitive(owner):
    def test(self):
        first, second = [build(owner, TIMES[0], changed) for changed in (False, True)]
        self.assertNotEqual(first, second)
    return test


for owner in ("prepare", "calibrate", "sync"):
    setattr(ArchiveTimes, f"test_{owner}_bytes_do_not_depend_on_encoding_time", stable(owner))
    setattr(ArchiveTimes, f"test_{owner}_different_contents_change_archive_bytes", sensitive(owner))

if __name__ == "__main__":
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(ArchiveTimes))
    Path(sys.argv[1]).write_text(json.dumps(OBSERVATIONS, indent=2) + "\n")
    sys.exit(not result.wasSuccessful())
