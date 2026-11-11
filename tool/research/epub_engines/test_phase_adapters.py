import json
from pathlib import Path
import subprocess
import unittest


class WebClockTest(unittest.TestCase):
    def test_conversion_uncertainty_includes_observed_browser_timer_precision(self):
        shell = (Path(__file__).parent / "assets/web/shell.html").read_text()
        script = shell.rsplit("<script>", 1)[1].split("</script>", 1)[0]
        program = """
            let ticks = 0;
            global.window = {};
            global.fetch = () => new Promise(() => {});
            global.performance = {now: () => Math.floor(++ticks / 10) / 10};
            global.Probe = {clockNs: () => String(1e9 + ticks * 10000)};
        """ + script + "\nconsole.log(JSON.stringify(calibrateClock()));"
        completed = subprocess.run(["node", "-e", program], capture_output=True, text=True, check=True)
        clock = json.loads(completed.stdout)
        self.assertGreaterEqual(clock["uncertainty_ns"], 100_000)
        self.assertAlmostEqual(clock.get("observed_resolution_ns", 0), 100_000, delta=1)


if __name__ == "__main__":
    unittest.main()
