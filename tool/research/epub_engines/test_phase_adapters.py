import json
from pathlib import Path
import re
import subprocess
import unittest


def run_shell(program):
    """Runs the web shell's inline scripts in Node with stubbed browser
    globals. runFrame(vsync) runs every animation frame callback requested
    so far, as one browser frame."""
    shell = (Path(__file__).parent / "assets/web/shell.html").read_text()
    script = "\n".join(re.findall(r"<script>(.*?)</script>", shell, re.S))
    prelude = """
        let ticks = 0;
        global.window = global;
        const animationFrames = [];
        global.requestAnimationFrame = callback => { animationFrames.push(callback); };
        const runFrame = vsync => animationFrames.splice(0).forEach(callback => callback(vsync));
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


class WebDrawingFrameTest(unittest.TestCase):
    def test_the_first_frame_after_preparation_the_next_vsync_and_the_page_text_are_reported_after_two_frames(self):
        report = run_shell("""
            const calls = [];
            Probe.frame = raw => calls.push(JSON.parse(raw));
            phaseClock = {offset_ns: 5000000};
            reportFrame("run/3", () => ({visible_text: "page"}));
            const requested = animationFrames.length;
            ticks = 989;
            runFrame(9.5);
            ticks = 1159;
            runFrame(26.2);
            const duringFrames = calls.length;
            setTimeout(() => console.log(JSON.stringify({requested, duringFrames, calls})));
        """)
        self.assertEqual((report["requested"], report["duringFrames"]), (1, 0))
        self.assertEqual(report["calls"], [{"preparation_event_id": "run/3", "frame_start_source_ms": 9.9,
                                            "frame_start_ns": 14_900_000, "frame_vsync_source_ms": 9.5,
                                            "frame_vsync_ns": 14_500_000, "next_frame_vsync_source_ms": 26.2,
                                            "next_frame_vsync_ns": 31_200_000, "visible_text": "page"}])

    def test_the_drawn_page_callback_is_requested_before_the_page_text_is_read(self):
        order = run_shell("""
            const order = [];
            const box = {left: 0, top: 0, right: 360, bottom: 640};
            const section = {sectionIndex: 0, range: () => ({startContainer: {textContent: "text"}, startOffset: 0,
                                                             endContainer: {}, endOffset: 0,
                                                             cloneRange() { return {setEnd() {}, toString: () => "page"}; }}),
                             document: {fonts: {ready: Promise.resolve()}, images: [],
                                        body: {get innerText() { order.push("text"); return "text"; }},
                                        documentElement: {getBoundingClientRect: () => box},
                                        defaultView: {frameElement: {getBoundingClientRect: () => box}}}};
            const place = {cfi: "epubcfi(/6/2)", index: 0, href: "a.xhtml", displayed: {page: 1, total: 2}};
            rendition = {getContents: () => [section], views: () => [],
                         currentLocation: () => ({start: place, end: place})};
            global.document = {getElementById: () => ({getBoundingClientRect: () => box})};
            global.requestAnimationFrame = callback => setTimeout(() => callback(0));
            Probe.ready = () => order.push("ready");
            Probe.frame = () => { order.push("frame"); console.log(JSON.stringify(order)); };
            phaseClock = {offset_ns: 0};
            report("page_turn", "run/3", 0, 0);
        """)
        self.assertEqual(order, ["ready", "text", "frame"])


# A page whose preparation is one frame long: the box, section and place that
# report() reads.
PAGE = """
    const box = {left: 0, top: 0, right: 360, bottom: 640};
    const section = {sectionIndex: 0, range: () => ({startContainer: {textContent: "text"}, startOffset: 0,
                                                     endContainer: {}, endOffset: 0,
                                                     cloneRange() { return {setEnd() {}, toString: () => "page"}; }}),
                     document: {fonts: {ready: Promise.resolve()}, images: [], body: {innerText: "text"},
                                documentElement: {getBoundingClientRect: () => box},
                                defaultView: {frameElement: {getBoundingClientRect: () => box}}}};
    const place = {cfi: "epubcfi(/6/2)", index: 0, href: "a.xhtml", displayed: {page: 1, total: 2}};
    rendition = {getContents: () => [section], views: () => [], currentLocation: () => ({start: place, end: place})};
    global.document = {getElementById: () => ({getBoundingClientRect: () => box})};
"""


class WebFrameWatchTest(unittest.TestCase):
    NO_FRAME = {"running_frame_vsync_source_ms": None, "running_frame_vsync_ns": None,
                "running_frame_start_source_ms": None, "running_frame_start_ns": None}

    def test_a_preparation_that_ends_inside_an_animation_frame_names_that_frame(self):
        frames = run_shell("""
            phaseClock = {offset_ns: 5000000};
            const seen = [];
            requestAnimationFrame(() => Promise.resolve().then(() => seen.push(runningFrame())));
            ticks = 989;
            runFrame(9.5);
            setTimeout(() => { seen.push(runningFrame()); console.log(JSON.stringify(seen)); });
        """)
        self.assertEqual(frames, [{"running_frame_vsync_source_ms": 9.5, "running_frame_vsync_ns": 14_500_000,
                                   "running_frame_start_source_ms": 9.9, "running_frame_start_ns": 14_900_000},
                                  self.NO_FRAME])

    def test_each_frame_counts_once_however_many_callbacks_it_runs(self):
        count = run_shell("""
            requestAnimationFrame(() => {});
            requestAnimationFrame(() => {});
            runFrame(9.5);
            requestAnimationFrame(() => {});
            runFrame(26.2);
            console.log(JSON.stringify(frameWatch.count));
        """)
        self.assertEqual(count, 2)

    def test_the_ready_report_names_the_running_frame_and_counts_the_frames_in_preparation(self):
        reports = run_shell(PAGE + """
            const readies = [];
            Probe.ready = raw => readies.push(JSON.parse(raw));
            Probe.frame = () => {};
            phaseClock = {offset_ns: 0};
            const before = frameWatch.count;
            requestAnimationFrame(() => {});
            runFrame(4.0);
            requestAnimationFrame(() => report("page_turn", "run/3", 0, before));
            runFrame(20.6);
            setTimeout(() => console.log(JSON.stringify(readies.map(ready =>
                [ready.frames_in_preparation, ready.running_frame_vsync_source_ms]))));
        """)
        self.assertEqual(reports, [[2, 20.6]])

    def test_a_preparation_that_ends_between_frames_names_no_running_frame(self):
        reports = run_shell(PAGE + """
            const readies = [];
            Probe.ready = raw => readies.push(JSON.parse(raw));
            Probe.frame = () => {};
            phaseClock = {offset_ns: 0};
            requestAnimationFrame(() => {});
            runFrame(4.0);
            setTimeout(() => report("page_turn", "run/3", 0, frameWatch.count));
            setTimeout(() => console.log(JSON.stringify(readies.map(ready =>
                [ready.frames_in_preparation, ready.running_frame_vsync_ns]))));
        """)
        self.assertEqual(reports, [[0, None]])

if __name__ == "__main__":
    unittest.main()
