import hashlib
import json
from pathlib import Path
import subprocess
import sys
import zlib

root = Path.cwd()
output = Path(__file__).resolve().parent
source = root / 'tool/evidence/reader/integrated/20261103/remaining/fixture.py'
program = source.read_text().split('os.umask(0o077)')[0]
program = program.replace('800 0 0 343 {column * 800}', '1400 0 0 343 {column * 800 + 100}').replace('column in range(2)', 'column in range(1)')
namespace = {'__file__': str(output / 'fixture.py')}
exec(compile(program, str(source), 'exec'), namespace)
marker = json.loads((root / '.cache/resumed-acceptance/owned-server.json').read_text())
server_root = Path(marker['root'])
destination = server_root / 'media/Acceptance single column.pdf'
namespace['scan_pdf'](destination)
sys.path.insert(0, str(root / 'tool/research/sync'))
from fixture import Api

accounts = json.loads((server_root / 'accounts.json').read_text())
api = Api(accounts['admin']['token'])
api.json('POST', '/Library/Refresh')
manifest = {'name': destination.name, 'sha256': hashlib.sha256(destination.read_bytes()).hexdigest(), 'bytes': destination.stat().st_size, 'imageDraws': 11, 'columns': 1, 'secondPage': 'blank', 'purpose': 'Reliable English order for completed retry and owned cache acceptance; dense fixture remains unchanged'}
(output / 'single-column.json').write_text(json.dumps(manifest, indent=2) + '\n')
print(json.dumps(manifest))
