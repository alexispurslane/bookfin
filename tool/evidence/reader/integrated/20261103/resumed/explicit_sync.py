import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import time

output = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('prior_ui', output.parent / 'remaining/ui.py')
ui = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ui)
ui.OUTPUT = output
ui.COMMAND = '/Users/alexispurslane/.t3/userdata/device/targets/t3-0c9013b2a0e9ae3418ba219d/agent-device'
prefix = sys.argv[1]
ui.run(prefix + '-relaunch', 'open', 'dev.bookfin.bookfin', '--relaunch')
ui.press(prefix + '-account', 'Account')
ui.run(prefix + '-account-state', 'snapshot', '--force-full')
subprocess.run([sys.executable, str(output / 'capture.py'), prefix + '-before'], check=True)
subprocess.run([sys.executable, str(output / 'server_readback.py'), prefix + '-server-before'], check=True)
routes = subprocess.check_output(['adb', '-s', 'emulator-5554', 'reverse', '--list']).decode()
assert 'tcp:7364' not in routes
events = [json.loads(line) for line in (output / 'events.ndjson').read_text().splitlines()]
launch = next(event for event in reversed(events) if event['evidence'] == prefix + '-relaunch.txt')
elapsed = time.time() - launch['start']
if elapsed >= 20:
    raise SystemExit('Startup exceeded the protected interval; route remains disconnected and no Sync input sent')
restored = time.time()
subprocess.run(['adb', '-s', 'emulator-5554', 'reverse', 'tcp:7364', 'tcp:7364'], check=True, capture_output=True)
ui.press(prefix + '-button', 'Sync now')
ui.run(prefix + '-result', 'snapshot', '--force-full')
subprocess.run([sys.executable, str(output / 'capture.py'), prefix + '-after'], check=True)
subprocess.run([sys.executable, str(output / 'server_readback.py'), prefix + '-server-after'], check=True)
(output / (prefix + '-timing.json')).write_text(json.dumps({'relaunchStart': launch['start'], 'routeRestored': restored, 'secondsFromRelaunchToRoute': elapsed, 'backgroundIntervalSeconds': 30, 'radiosChangedDuringRouteAndButton': False, 'routeWasAbsentBeforeButton': True}, indent=2) + '\n')
