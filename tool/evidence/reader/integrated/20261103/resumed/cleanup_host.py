import json
import os
from pathlib import Path
import shutil
import signal
import socket
import subprocess
import sys

output = Path(__file__).resolve().parent
root = Path.cwd()
private = root / '.cache/resumed-acceptance'
marker = json.loads((private / 'owned-server.json').read_text())
server_root = Path(marker['root'])
assert server_root.parent == root / '.cache/plugin' and server_root.name.startswith('run-')
baseline = {row['identity'] for row in json.loads((output / 'baseline.json').read_text())['actions']}
final = json.loads((output / 'final-retained.json').read_text())
remote = {row['identity']: row for row in json.loads((output / 'final-server.json').read_text())['objects']}
new = [row for row in final['actions'] if row['identity'] not in baseline]
for row in new:
    assert row['pending'] == 0
    assert remote[row['identity']]['payloadSha256'] == row['payloadSha256']
    assert remote[row['identity']]['action'] == row['action']
if sys.argv[1] == 'stop':
    command = subprocess.check_output(['ps', '-p', str(marker['controllerPid']), '-o', 'command=']).decode()
    assert 'resumed/fixture.py' in command
    os.kill(marker['controllerPid'], signal.SIGTERM)
    print('Stopped the verified owned controller; wait for its completion before removing private data.')
elif sys.argv[1] == 'remove':
    for process in [marker['controllerPid'], marker['serverPid']]:
        status = subprocess.run(['ps', '-p', str(process), '-o', 'command='], capture_output=True)
        assert not status.stdout.strip(), process
    for port in (7364, 7365):
        with socket.socket() as listener:
            listener.bind(('127.0.0.1', port))
    routes = subprocess.check_output(['adb', '-s', 'emulator-5554', 'reverse', '--list']).decode()
    assert 'tcp:7364' not in routes
    shutil.rmtree(server_root)
    shutil.rmtree(private)
    result = {'ownedProcessesAbsent': True, 'ownedPortsFree': True, 'ownedRouteAbsent': True, 'ownedPrivateFixtureRemoved': True, 'newActionsVerifiedBeforeDeletion': len(new), 'newPendingActions': 0, 'recoveryBackupRequiredForNewAccount': False, 'originalAccountRecovery': 'No authentic original account state recovered; no prior backup searched or removed in this lane'}
    (output / 'host-cleanup.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result))
else:
    raise SystemExit('Use stop or remove')
