import hashlib
import json
from pathlib import Path


OUTPUT = Path(__file__).resolve().parent
baseline = json.loads((OUTPUT / 'baseline.json').read_text())
targets = {row['accountSha256'] for row in baseline['actions'] if row['pending']}
roots = [Path('/Users/alexispurslane/Development/bookfin')]
roots.extend(path for path in Path('/Users/alexispurslane/.t3/worktrees/bookfin').iterdir() if path.is_dir())
inventory = []
for root in roots:
    candidates = [root / '.cache/sync/runtime/accounts.json']
    candidates.extend((root / '.cache/plugin').glob('run-*/accounts.json'))
    for path in candidates:
        if not path.is_file():
            continue
        directory = path.parent
        fixture_path = directory / 'fixture.json'
        fixture = json.loads(fixture_path.read_text()) if fixture_path.exists() else {}
        device = directory / 'data/data/device.txt'
        server_id = fixture.get('serverId') or (device.read_text().strip() if device.exists() else None)
        accounts = json.loads(path.read_text())
        origins = {fixture.get('origin', 'http://127.0.0.1:7364'), 'http://127.0.0.1:7364', 'http://127.0.0.1:7464'}
        matches = []
        if server_id:
            for account in accounts.values():
                if not isinstance(account, dict) or not account.get('id'):
                    continue
                for origin in origins:
                    scope = json.dumps([origin.rstrip('/'), server_id, account['id']], separators=(',', ':'))
                    digest = hashlib.sha256(scope.encode()).hexdigest()
                    if digest in targets:
                        matches.append(digest)
        inventory.append({'fixture': str(path.relative_to(root)), 'checkout': root.name, 'serverIdentityAvailable': bool(server_id), 'serverDatabaseAvailable': (directory / 'data/data/jellyfin.db').is_file(), 'privatePasswordFileAvailable': (directory / 'passwords.json').is_file(), 'matchingOriginalPendingAccounts': sorted(set(matches))})
result = {'scope': 'Read-only existing conventional sync/plugin fixture backups in main and all local T3 worktrees; no identity creation or server startup.', 'targetPendingAccounts': sorted(targets), 'candidateFixtures': inventory, 'matchingFixtures': sum(bool(item['matchingOriginalPendingAccounts']) for item in inventory)}
(OUTPUT / 'recovery-inventory.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps({'candidates': len(inventory), 'matchingFixtures': result['matchingFixtures']}))
