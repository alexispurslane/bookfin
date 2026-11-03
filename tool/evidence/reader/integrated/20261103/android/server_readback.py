import hashlib
import json
from pathlib import Path
import sys


ROOT = Path.cwd()
OUTPUT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / 'tool/research/sync'))
from fixture import Api


case = sys.argv[1]
if not case.replace('-', '').isalnum():
    raise SystemExit('Use a simple evidence name')
marker = json.loads((ROOT / '.cache/combined-acceptance/owned-server.json').read_text())
private = Path(marker['root'])
accounts = json.loads((private / 'accounts.json').read_text())
public = Api().json('GET', '/System/Info/Public')
assert public['Id'] == marker['serverId'] and public['Version'] == '12.4.0'
api = Api(accounts['alice']['token'])
objects = []
cursor = 0
for page_number in range(100):
    page = api.json('GET', f'/BookfinStorage/v1/objects?after={cursor}&limit=4')
    for stored in page['Objects']:
        payload = stored['Payload']
        action = json.loads(payload)
        action['account'] = hashlib.sha256(action['account'].encode()).hexdigest()
        objects.append({'identity': stored['Id'], 'sequence': stored['Sequence'],
                        'payloadSha256': hashlib.sha256(payload.encode()).hexdigest(), 'action': action})
    cursor = page['Cursor']
    if not page['HasMore']:
        break
else:
    raise RuntimeError('Unbounded ordinary fixture inventory')
result = {'case': case, 'serverVersion': public['Version'], 'cursor': cursor, 'objects': objects}
(OUTPUT / f'{case}-server.json').write_text(json.dumps(result, indent=2, ensure_ascii=False) + '\n')
books = api.json('GET', f'/Users/{accounts["alice"]["id"]}/Items?recursive=true&includeItemTypes=Book')['Items']
details = [api.json('GET', f'/Users/{accounts["alice"]["id"]}/Items/{book["Id"]}') for book in books]
(OUTPUT / 'ordinary-book-dtos.json').write_text(json.dumps(details, indent=2) + '\n')
print(json.dumps({'case': case, 'actualPluginObjects': len(objects), 'ordinaryBooks': len(details),
                  'allOmitContainerAndMediaSources': all('Container' not in book and 'MediaSources' not in book for book in details)}))
