import json
import os
from pathlib import Path
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tool/research/plugin'))
from dedicated_fixture import Server


def main():
    build = ROOT / '.cache/plugin/build'
    subprocess.run([
        'dotnet', 'build', 'tool/research/plugin/Bookfin.Storage.csproj',
        '-c', 'Release', '-p:JellyfinDir=' + os.environ['BOOKFIN_SYNC_SERVER'],
        '-o', str(build), '--nologo',
    ], cwd=ROOT, check=True)
    server = Server()
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
        result = subprocess.run([
            'nix', 'develop', '--command', 'flutter', 'test', '--no-pub', 'test/sync/plugin_integration_test.dart',
            '--concurrency=1', '--reporter', 'expanded',
        ], cwd=ROOT, env={**os.environ, 'BOOKFIN_PRODUCTION_SYNC_FIXTURE': str(config)})
        return result.returncode
    finally:
        server.stop()


if __name__ == '__main__':
    sys.exit(main())
