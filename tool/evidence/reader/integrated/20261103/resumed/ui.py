import importlib.util
import json
from pathlib import Path
import subprocess
import sys

output = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('prior_ui', output.parent / 'remaining/ui.py')
prior = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prior)
prior.OUTPUT = output
prior.COMMAND = '/Users/alexispurslane/.t3/userdata/device/targets/t3-0c9013b2a0e9ae3418ba219d/agent-device'
name, operation, *arguments = sys.argv[1:]
if operation == 'press':
    prior.press(name, *arguments)
    prior.run(name + '-after', 'snapshot', '--force-full')
elif operation == 'credential':
    field, key = arguments
    marker = json.loads((Path.cwd() / '.cache/resumed-acceptance/owned-server.json').read_text())
    passwords = json.loads((Path(marker['root']) / 'passwords.json').read_text())
    snapshot = prior.run(name + '-before', 'snapshot', '--force-full')
    if field not in snapshot:
        raise SystemExit('Exact field reference absent; no input sent')
    value = passwords[key]
    result = subprocess.run([prior.COMMAND, 'fill', field, value, '--settle'], capture_output=True, text=True)
    (output / f'{name}.txt').write_text(json.dumps({'exit': result.returncode, 'credentialOutputRedacted': True}) + '\n')
    print('Credential input result:', result.returncode)
    if result.returncode:
        print(result.stderr.replace(value, '[redacted]'))
        raise SystemExit(result.returncode)
else:
    if operation == 'fill':
        prior.run(name + '-before', 'snapshot', '--force-full')
    prior.run(name, operation, *arguments)
