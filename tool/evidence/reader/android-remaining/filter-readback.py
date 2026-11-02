import json
import re
import sys
import xml.etree.ElementTree as xml
from datetime import datetime, timezone
from pathlib import Path


accounts = json.loads(Path('.cache/sync/runtime/accounts.json').read_text())
marker = json.loads(Path('.cache/sync/runtime/fixture.json').read_text())
user = accounts['alice']['id']
scope = ['http://127.0.0.1:7365', marker['serverId'], user]
records = []
for element in xml.parse('.cache/current-reader.xml').getroot():
    name = element.get('name', '')
    if name.startswith('flutter.bookfin.playback.v1.'):
        account = json.loads(name.removeprefix('flutter.bookfin.playback.v1.'))
        if account == scope:
            records.append(json.loads(element.text)['reading'])
if len(records) != 1:
    raise RuntimeError('Expected exactly this fixture account reading record')
appearance = None
data = Path('.cache/current-theme.pb').read_bytes()
for match in re.finditer(rb'\{"version":1,"mode":', data):
    candidate, length = json.JSONDecoder().raw_decode(data[match.start():].decode(errors='replace'))
    if candidate.get('mode') in ['automatic', 'day', 'night']:
        appearance = candidate
output = {'at': datetime.now(timezone.utc).isoformat(), 'case': sys.argv[1], 'scope': scope, 'appearance': appearance, 'reading': records[0]}
print(json.dumps(output, indent=2))
