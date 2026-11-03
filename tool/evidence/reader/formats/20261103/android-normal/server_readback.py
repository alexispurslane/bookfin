"""Read the existing plugin API for this checkout's disposable accounts only."""

import hashlib
import json
from pathlib import Path
import sys

root = Path.cwd()
sys.path.insert(0, str(root / 'tool/research/sync'))
import fixture

case = sys.argv[1]
if not case.replace('-', '').isalnum():
    raise SystemExit('Use a simple case name')
accounts = json.loads((fixture.ROOT / 'accounts.json').read_text())
marker = json.loads((fixture.ROOT / 'fixture.json').read_text())
public = fixture.Api().json('GET', '/System/Info/Public')
assert public['Id'] == marker['serverId'] and public['Version'] == '12.4.0'
package = root / '.cache/plugin/package/Bookfin.Storage_0.1.1.0.zip'
package_hash = hashlib.sha256(package.read_bytes()).hexdigest()
assert package_hash == '3b0de5ca1df39baf67c786079898b1ee3b0b09d3bdb86d00ece8a7f5731a9105'
output = {'case': case, 'serverVersion': public['Version'], 'pluginPackageSha256': package_hash,
          'scope': 'Read-only actual plugin API; ordinary fixture accounts, not a second Android device',
          'accounts': {}}
for name in ['alice', 'bob']:
    api = fixture.Api(accounts[name]['token'])
    cursor = 0
    objects = []
    for page_number in range(100):
        page = api.json('GET', f'/BookfinStorage/v1/objects?after={cursor}&limit=4')
        for stored in page['Objects']:
            payload = stored['Payload']
            action = json.loads(payload) if payload else None
            if action:
                action['account'] = 'owned-ordinary-account'
            objects.append({'identity': stored['Id'], 'sequence': stored['Sequence'],
                            'payloadSha256': hashlib.sha256(payload.encode()).hexdigest() if payload else None,
                            'action': action})
        cursor = page['Cursor']
        if not page['HasMore']:
            break
    else:
        raise RuntimeError('Unexpected unbounded fixture inventory')
    output['accounts'][name] = {'cursor': cursor, 'objects': objects}
(Path(__file__).resolve().parent / f'{case}-server.json').write_text(json.dumps(output, indent=2) + '\n')
print(json.dumps({'case': case, 'serverVersion': public['Version'],
                  'aliceObjects': len(output['accounts']['alice']['objects']),
                  'bobObjects': len(output['accounts']['bob']['objects'])}))
