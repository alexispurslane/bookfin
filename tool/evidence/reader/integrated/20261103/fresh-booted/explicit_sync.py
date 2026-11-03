import json
import os
from pathlib import Path
import subprocess
import sys
import time

output = Path(__file__).resolve().parent
command = os.environ['BOOKFIN_AGENT_DEVICE']
case = sys.argv[1] if len(sys.argv) > 1 else 'explicit'
started = time.time()
subprocess.run([command, 'open', 'dev.bookfin.bookfin', '--relaunch'], check=True)
subprocess.run(['python3', str(output / 'ui.py'), f'{case}-account', 'Account'], check=True)
subprocess.run(['adb', '-s', 'emulator-5556', 'reverse', 'tcp:7364', 'tcp:7364'], check=True)
restored = time.time()
subprocess.run(['adb', '-s', 'emulator-5556', 'reverse', '--list'], check=True, stdout=(output / f'{case}-restored-routes.txt').open('w'))
dispatch = time.time()
subprocess.run(['python3', str(output / 'ui.py'), f'{case}-sync', 'Sync now'], check=True)
result = {'launchStartedUnix': started, 'routeRestoredUnix': restored, 'buttonCommandStartedUnix': dispatch, 'buttonCommandCompletedUnix': time.time()}
(output / f'{case}-timing.json').write_text(json.dumps(result, indent=2) + '\n')
assert result['buttonCommandCompletedUnix'] - started < 30
print(json.dumps(result))
