import json
from pathlib import Path
import re
import subprocess
import sys
import time


OUTPUT = Path(__file__).resolve().parent
COMMAND = '/Users/alexispurslane/.t3/userdata/device/targets/t3-e7ee98e4e6483c63952df0a5/agent-device'


def run(name, *arguments):
    start = time.time()
    result = subprocess.run([COMMAND, *arguments], capture_output=True, text=True)
    (OUTPUT / f'{name}.txt').write_text(result.stdout + result.stderr)
    with (OUTPUT / 'events.ndjson').open('a') as events:
        events.write(json.dumps({'start': start, 'end': time.time(), 'arguments': arguments, 'exit': result.returncode, 'evidence': f'{name}.txt'}) + '\n')
    print(result.stdout + result.stderr, end='')
    if result.returncode:
        raise SystemExit(result.returncode)
    return result.stdout


def press(name, label, role='button'):
    snapshot = run(name + '-before', 'snapshot', '--force-full')
    pattern = r'(@e\d+) \[' + re.escape(role) + r'\] "' + re.escape(label) + r'"(?: \[[^\]]+\])*\s*$'
    matches = re.findall(pattern, snapshot, flags=re.M)
    if len(matches) != 1:
        raise SystemExit(f'Expected exactly one fresh {role} named {label}; found {len(matches)}. No input dispatched.')
    return run(name, 'press', matches[0], '--settle')


if __name__ == '__main__':
    name, operation, *arguments = sys.argv[1:]
    if operation == 'press':
        press(name, *arguments)
        run(name + '-after', 'snapshot', '--force-full')
    else:
        run(name, operation, *arguments)
