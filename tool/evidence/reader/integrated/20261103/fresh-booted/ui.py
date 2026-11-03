import os
from pathlib import Path
import re
import subprocess
import sys

command = os.environ['BOOKFIN_AGENT_DEVICE']
output = Path(__file__).resolve().parent
case, label = sys.argv[1:3]
kind = sys.argv[3] if len(sys.argv) > 3 else 'button'
assert kind in ('button', 'group')
snapshot = subprocess.check_output([command, 'snapshot', '--force-full'], text=True)
(output / f'{case}-before.txt').write_text(snapshot)
matches = re.findall(r'^\s*(@e\d+) \[' + kind + r'\] "' + re.escape(label) + r'"(?: \[.*\])?$', snapshot, re.MULTILINE)
if len(matches) != 1:
    raise RuntimeError(f'Expected one exact button {label!r}; found {len(matches)}')
result = subprocess.check_output([command, 'press', matches[0], '--settle'], text=True)
(output / f'{case}-action.txt').write_text(result)
snapshot = subprocess.check_output([command, 'snapshot', '--force-full'], text=True)
(output / f'{case}-after.txt').write_text(snapshot)
print(snapshot)
