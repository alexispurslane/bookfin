import hashlib
import json
import os
from pathlib import Path
import subprocess
import time


ROOT = Path.cwd()
OUTPUT = Path(__file__).resolve().parent
NAME = 'bookfin-accept-20261103-db111f95'
AVD = Path.home() / '.android/avd' / f'{NAME}.avd'
HOST_SDK = Path.home() / 'Library/Android/sdk'
ARTIFACT = Path('/Users/alexispurslane/.t3/worktrees/bookfin/t3-f29350e1/.cache/artifacts/bookfin-d8e1021-cancel')
EXPECTED = {
    ARTIFACT / 'bookfin-d8e1021-arm64-debug.apk': '8b31c7448f746226453d4677f944c9ba4f5668f657bba8015f94973372744e09',
    ARTIFACT / 'source/bookfin-source.tar': '3dd0c18fb2cdc3b94e8831f12b4ef92d573bccd73392a626b3c46de1dae45f60',
    Path('/Users/alexispurslane/.t3/worktrees/bookfin/t3-2ef60719/.cache/plugin/package/Bookfin.Storage_0.1.1.0.zip'): '3b0de5ca1df39baf67c786079898b1ee3b0b09d3bdb86d00ece8a7f5731a9105',
}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def config_values(path):
    return dict(
        (key.strip(), value.strip())
        for line in path.read_text().splitlines()
        if '=' in line
        for key, value in [line.split('=', 1)]
    )


sdk = Path(os.environ['ANDROID_HOME'])
configuration = config_values(AVD / 'config.ini')
relative_image = configuration['image.sysdir.1']
assert not Path(relative_image).is_absolute()
assert not (HOST_SDK / relative_image).exists()
assert (sdk / relative_image / 'source.properties').is_file()
assert (sdk / relative_image / 'system.img').is_file()
artifacts = []
for path, expected in EXPECTED.items():
    actual = digest(path)
    assert actual == expected, path.name
    artifacts.append({'path': str(path), 'sha256': actual, 'bytes': path.stat().st_size})
files = [
    {'path': str(path.relative_to(AVD)), 'bytes': path.stat().st_size, 'sha256': digest(path)}
    for path in sorted(AVD.rglob('*')) if path.is_file()
]
assert [entry['path'] for entry in files] == ['config.ini']
discovery = json.loads((OUTPUT / 'device-discovery.json').read_text())
assert discovery['afterProvisioningAndAtFinish']['open'] == []
assert not discovery['boundCommandReturned']
prior = json.loads((OUTPUT.parent / 'resumed/final-retained.json').read_text())
assert len(prior['actions']) == 79
assert sum(row['pending'] for row in prior['actions']) == 28
report = {
    'timeUnix': time.time(),
    'baseCommit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
    'artifactSourceCommit': 'd8e1021fef2be69291d135594a45d556570c235f',
    'ownedAvd': {'name': NAME, 'path': str(AVD), 'files': files, 'hostId': 'local', 'deviceId': NAME, 'booted': False},
    'sdkMismatch': {'hostEmulator': str(HOST_SDK / 'emulator/emulator'), 'relativeImage': relative_image, 'hostImageExists': False, 'nixSdk': str(sdk), 'nixImageExists': True, 'nativeStderrAvailable': False, 'soleFailureCauseConfirmed': False},
    'artifacts': artifacts,
    'runtimeAcceptance': {'freshInstallOfflineOcr': 'blocked-before-install', 'firstPrivateModelCopy': 'unverified', 'reflowSearchOriginalBookmark': 'unverified', 'cachedOfflineProcessRestart': 'unverified', 'unicodePendingAndExplicitSync': 'blocked-before-account-creation', 'lostAcknowledgmentRetry': 'unverified', 'crossAccountOcrOwnership': 'unverified'},
    'retainedDevice': {'id': 'emulator-5554', 'openedByThisLane': False, 'operatedByThisLane': False, 'previousEvidenceActions': 79, 'previousEvidencePending': 28, 'countsAreFreshlyMeasured': False, 'previousEvidenceSha256': digest(OUTPUT.parent / 'resumed/final-retained.json')},
    'cleanup': {'newAvdUnbootedNoBinding': True, 'fixtureStarted': False, 'routeCreated': False, 'credentialsCreated': False, 'newPersonalActionsCreated': False, 'apkInstalled': False, 'settingsChanged': False, 'retainedAvdModified': False, 'newAvdDeleted': False},
}
(OUTPUT / 'public-audit.json').write_text(json.dumps(report, indent=2) + '\n')
print('PASS: scoped provisioning/artifact audit; runtime OCR and pending acceptance remain blocked, not passed.')
