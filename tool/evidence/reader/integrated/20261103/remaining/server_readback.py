import hashlib
import json
from pathlib import Path
import sys
import time


ROOT = Path.cwd()
OUTPUT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / 'tool/research/sync'))
from fixture import Api


marker = json.loads((ROOT / '.cache/remaining-acceptance/owned-server.json').read_text())
accounts = json.loads((Path(marker['root']) / 'accounts.json').read_text())
api = Api(accounts['alice']['token'])
public = api.json('GET', '/System/Info/Public')
assert public['Id'] == marker['serverId'] and public['Version'] == '12.4.0'
objects = []
cursor = 0
for page_number in range(100):
    page = api.json('GET', f'/BookfinStorage/v1/objects?after={cursor}&limit=4')
    for stored in page['Objects']:
        payload = stored['Payload']
        action = json.loads(payload)
        action['account'] = hashlib.sha256(action['account'].encode()).hexdigest()
        objects.append({'identity': stored['Id'], 'sequence': stored['Sequence'], 'payloadSha256': hashlib.sha256(payload.encode()).hexdigest(), 'action': action})
    cursor = page['Cursor']
    if not page['HasMore']:
        break
else:
    raise RuntimeError('Unbounded plugin inventory')
items = api.json('GET', f'/Users/{accounts["alice"]["id"]}/Items?recursive=true&includeItemTypes=Book')['Items']
details = [api.json('GET', f'/Users/{accounts["alice"]["id"]}/Items/{item["Id"]}') for item in items]
result = {'timeUnix': time.time(), 'serverVersion': public['Version'], 'cursor': cursor, 'objects': objects, 'ordinaryOriginals': [{'name': item['Name'], 'id': item['Id'], 'containerOmitted': 'Container' not in item, 'mediaSourcesOmitted': 'MediaSources' not in item} for item in details]}
(OUTPUT / 'stop-server.json').write_text(json.dumps(result, indent=2, ensure_ascii=False) + '\n')
print(json.dumps({'objects': len(objects), 'ordinaryOriginals': len(items)}))
