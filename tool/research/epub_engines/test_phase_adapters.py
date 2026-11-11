import json
from pathlib import Path
import subprocess
import unittest


def run_shell(program):
    """Runs the web shell's script in Node with stubbed browser globals."""
    shell = (Path(__file__).parent / "assets/web/shell.html").read_text()
    script = shell.rsplit("<script>", 1)[1].split("</script>", 1)[0]
    prelude = """
        let ticks = 0;
        global.window = {};
        global.fetch = () => new Promise(() => {});
        global.performance = {now: () => Math.floor(++ticks / 10) / 10};
        global.Probe = {clockNs: () => String(1e9 + ticks * 10000)};
    """
    completed = subprocess.run(["node", "-e", prelude + script + "\n" + program],
                               capture_output=True, text=True, check=True)
    return json.loads(completed.stdout)


class WebClockTest(unittest.TestCase):
    def test_conversion_uncertainty_includes_observed_browser_timer_precision(self):
        clock = run_shell("console.log(JSON.stringify(calibrateClock()));")
        self.assertGreaterEqual(clock["uncertainty_ns"], 100_000)
        self.assertAlmostEqual(clock.get("observed_resolution_ns", 0), 100_000, delta=1)


class WebPageImagesTest(unittest.TestCase):
    def test_only_images_on_the_shown_page_are_awaited(self):
        # epub.js scrolls a wide section frame under a 360 px reader; the
        # frame's left edge is 720 px to the left of the reader.
        names = run_shell("""
            const box = (left, top, width, height) => ({left, top, right: left + width, bottom: top + height});
            const image = (name, left) => ({name, getBoundingClientRect: () => box(left, 100, 200, 150)});
            const content = {document: {images: [image("previous page", 0), image("shown page", 730),
                                                  image("next page", 1100), image("edge", 1080)],
                                        defaultView: {frameElement: {getBoundingClientRect: () => box(-720, 0, 2160, 640)}}}};
            console.log(JSON.stringify(pageImages([content], box(0, 0, 360, 640)).map(image => image.name)));
        """)
        self.assertEqual(names, ["shown page"])


if __name__ == "__main__":
    unittest.main()
