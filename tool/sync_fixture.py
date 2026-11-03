import json
import os
from pathlib import Path
import shutil
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tool/research/plugin'))
from dedicated_fixture import Server
sys.path.insert(0, str(ROOT / 'tool/plugin'))
from package import build


def main():
    archive = build(ROOT / '.cache/plugin/package')
    server = Server(archive)
    try:
        server.start()
        server.seed()
        session = server.accounts['alice']
        config = server.root / 'production-client.json'
        config.write_text(json.dumps({
            'scope': {'server': 'http://127.0.0.1:7464', 'serverId': server.server_id, 'userId': session['id']},
            'token': session['token'], 'username': 'Alice', 'canDownload': True,
        }))
        config.chmod(0o600)
        format_session = server.accounts['bob']
        format_config = server.root / 'format-client.json'
        format_config.write_text(json.dumps({
            'scope': {'server': 'http://127.0.0.1:7464', 'serverId': server.server_id, 'userId': format_session['id']},
            'token': format_session['token'], 'username': 'Bob', 'canDownload': True,
        }))
        format_config.chmod(0o600)
        result = subprocess.run([
            'nix', 'develop', '--command', 'flutter', 'test', '--no-pub',
            'test/sync/plugin_integration_test.dart', 'test/sync/format_retry_test.dart',
            '--concurrency=1', '--reporter', 'expanded',
        ], cwd=ROOT, env={**os.environ, 'BOOKFIN_PRODUCTION_SYNC_FIXTURE': str(config),
                         'BOOKFIN_FORMAT_SYNC_FIXTURE': str(format_config)})
        return result.returncode
    finally:
        server.stop()
        shutil.rmtree(server.root)
        print('Owned loopback plugin fixture stopped; disposable data and credentials removed.', flush=True)


if __name__ == '__main__':
    sys.exit(main())
