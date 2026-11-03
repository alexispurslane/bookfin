import hashlib
import json
from pathlib import Path
import subprocess

output = Path(__file__).resolve().parent
root = Path.cwd()


def adb(*arguments):
    return subprocess.check_output(['adb', '-s', 'emulator-5554', *arguments])


artifact = json.loads((root / 'tool/evidence/reader/cancel-rendering/20261103/artifact.json').read_text())
package_path = adb('shell', 'pm', 'path', 'dev.bookfin.bookfin').decode().strip().removeprefix('package:')
installed_hash = adb('shell', 'sha256sum', package_path).decode().split()[0]
assert installed_hash == artifact['apkSha256']
for field, expected in [('apk', 'apkSha256'), ('sourceArchive', 'sourceArchiveSha256')]:
    with Path(artifact[field]).open('rb') as stream:
        assert hashlib.file_digest(stream, 'sha256').hexdigest() == artifact[expected]
result = {'sourceCommit': artifact['sourceCommit'], 'apkSha256': installed_hash, 'sourceArchiveSha256': artifact['sourceArchiveSha256'], 'entrypoint': artifact['entrypoint'], 'package': artifact['package'], 'installation': 'In-place adb install -r succeeded; no rebuild, uninstall, reset, or private database write.'}
(output / 'artifact.json').write_text(json.dumps(result, indent=2) + '\n')
process = adb('shell', 'pidof', 'dev.bookfin.bookfin').decode().strip()
logs = adb('logcat', '-d', '-v', 'brief', '--pid=' + process).decode(errors='replace')
summary = {'pid': process, 'scope': 'Read-only log buffer for the current app process, not every earlier process in this lane', 'linesRead': len(logs.splitlines()), 'nullCheckErrorLines': sum('Null check operator used on a null value' in line for line in logs.splitlines()), 'fatalExceptionLines': sum('FATAL EXCEPTION' in line for line in logs.splitlines()), 'rawLogsRetained': False}
(output / 'app-log-summary.json').write_text(json.dumps(summary, indent=2) + '\n')
marker = json.loads((root / '.cache/resumed-acceptance/owned-server.json').read_text())
server = Path(marker['root'])
passwords = json.loads((server / 'passwords.json').read_text())
accounts = json.loads((server / 'accounts.json').read_text())
secrets = list(passwords.values()) + [account['token'] for account in accounts.values()]
for path in output.iterdir():
    if path.is_file():
        content = path.read_bytes()
        assert not any(secret.encode() in content for secret in secrets), path.name
print(json.dumps({'installedApkMatches': True, 'sourceArchiveMatches': True, 'credentialScan': 'No owned password or token in evidence', 'appLogSummary': summary}))
