"""Prepare and verify only the selected, bundled English-fast OCR inputs."""

import argparse
import hashlib
import json
import os
import re
from pathlib import Path
import shutil
import struct
import subprocess
import tarfile
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[2]
PINS = {
    'BOOKFIN_OCR_MODEL': '7d4322bd2a7749724879683fc3912cb542f19906c83bcc1a52132556427170b2',
    'BOOKFIN_OCR_ANDROID_AAR': 'bce5d6413a1a5ae3d7240033fbbc851ba3217d0a08d9769400e17a077f42cb2a',
    'BOOKFIN_OCR_ANDROID_SOURCE': '4569f9093d641d13188ba2dd36a74396661eaa3f9e44637ff1cac9a36076a20e',
    'BOOKFIN_OCR_MODEL_LICENSE': 'cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30',
}
NOTICES = {
    'Tesseract4Android.txt': ('LICENSE', 'Tesseract4Android 4.9.0 (Apache-2.0)'),
    'Tesseract.txt': ('tesseract4android/src/main/cpp/tesseract/src/LICENSE', 'Tesseract 5.5.1 (Apache-2.0)'),
    'Leptonica.txt': ('tesseract4android/src/main/cpp/leptonica/src/leptonica-license.txt', 'Leptonica 1.85.0'),
    'libpng.txt': ('tesseract4android/src/main/cpp/libpng/src/LICENSE', 'Tesseract4Android bundled libpng'),
    'libjpeg.txt': ('tesseract4android/src/main/cpp/libjpeg/src/README', 'Tesseract4Android bundled Independent JPEG Group libjpeg'),
}


def digest(payload):
    return hashlib.sha256(payload).hexdigest()


def inputs():
    paths = {key: Path(os.environ[key]) for key in PINS}
    for key, path in paths.items():
        if digest(path.read_bytes()) != PINS[key]:
            raise ValueError('Pinned OCR input changed: ' + key)
    if paths['BOOKFIN_OCR_MODEL'].stat().st_size != 4113088:
        raise ValueError('The selected English-fast model must be 4113088 bytes.')
    return paths


def prepare(notices=False):
    paths = inputs()
    assets = ROOT / '.cache/ocr/bundle/bookfin-ocr'
    assets.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(paths['BOOKFIN_OCR_MODEL'], assets / 'eng.traineddata')
    revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    stamp = {
        'sourceCommit': revision,
        'clean': not bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT).strip()),
        'sourceArchiveSha256': digest(subprocess.check_output(['git', 'archive', '--format=tar', revision], cwd=ROOT)),
    }
    (assets.parent / 'bookfin-source.json').write_text(json.dumps(stamp, indent=2) + '\n')
    if notices:
        directory = ROOT / 'assets/licenses/ocr'
        directory.mkdir(parents=True, exist_ok=True)
        manifest = {}
        with tarfile.open(paths['BOOKFIN_OCR_ANDROID_SOURCE']) as archive:
            for name, (source, package) in NOTICES.items():
                payload = archive.extractfile('Tesseract4Android-4.9.0/' + source).read()
                (directory / name).write_bytes(payload)
                manifest[name] = {'package': package, 'sha256': digest(payload)}
        payload = paths['BOOKFIN_OCR_MODEL_LICENSE'].read_bytes()
        (directory / 'English-fast.txt').write_bytes(payload)
        manifest['English-fast.txt'] = {'package': 'tessdata_fast 4.1.0 English (Apache-2.0)', 'sha256': digest(payload)}
        payload = (
            'Bookfin bundles Tesseract4Android 4.9.0, Tesseract 5.5.1, Leptonica 1.85.0, '
            'and the tessdata_fast 4.1.0 English model.\n'
            'This software is based in part on the work of the Independent JPEG Group.\n'
            'Original engine, model, libpng, Leptonica and IJG notices accompany this acknowledgement.\n'
            'English is the only supported recognition language. No model download or cloud recognition is used.\n'
        ).encode()
        (directory / 'Bookfin-OCR-NOTICE.txt').write_bytes(payload)
        manifest['Bookfin-OCR-NOTICE.txt'] = {'package': 'Bookfin OCR acknowledgements', 'sha256': digest(payload)}
        (directory / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print('Verified and prepared the selected English-fast model and pinned OCR inputs.')


def alignments(payload):
    if payload[:6] != b'\x7fELF\x02\x01':
        raise ValueError('An Android native library is not little-endian ELF64.')
    offset = struct.unpack_from('<Q', payload, 32)[0]
    size, count = struct.unpack_from('<HH', payload, 54)
    return [struct.unpack_from('<Q', payload, offset + index * size + 48)[0]
            for index in range(count)
            if struct.unpack_from('<I', payload, offset + index * size)[0] == 1]


def verify(apk):
    paths = inputs()
    with ZipFile(apk) as archive, ZipFile(paths['BOOKFIN_OCR_ANDROID_AAR']) as aar:
        names = archive.namelist()
        if len(names) != len(set(names)):
            raise ValueError('Duplicate APK entries are not accepted.')
        stamp = json.loads(archive.read('assets/bookfin-source.json'))
        if stamp.get('clean') is not True or not re.fullmatch('[0-9a-f]{40}', stamp.get('sourceCommit', '')):
            raise ValueError('The production handoff requires a committed, clean source snapshot.')
        source_archive = subprocess.check_output(['git', 'archive', '--format=tar', stamp['sourceCommit']], cwd=ROOT)
        if digest(source_archive) != stamp.get('sourceArchiveSha256'):
            raise ValueError('The packaged source stamp does not match its exact Git archive.')
        model_names = [name for name in names if name.endswith('.traineddata')]
        if model_names != ['assets/bookfin-ocr/eng.traineddata']:
            raise ValueError('The package must contain only the selected bundled English model.')
        if digest(archive.read(model_names[0])) != PINS['BOOKFIN_OCR_MODEL']:
            raise ValueError('The packaged English model changed.')
        if any('mlkit' in name.lower() for name in names):
            raise ValueError('The selected OCR stack must not contain ML Kit assets.')
        native = []
        for name in names:
            if not name.startswith('lib/') or not name.endswith('.so'):
                continue
            if not name.startswith('lib/arm64-v8a/'):
                raise ValueError('The ARM64 handoff unexpectedly contains another native architecture.')
            payload = archive.read(name)
            values = alignments(payload)
            if not values or min(values) < 16384:
                raise ValueError('Native library lacks 16 KiB ELF alignment: ' + name)
            native.append({'file': name, 'sha256': digest(payload), 'loadAlignments': values})
        selected = {}
        for name in aar.namelist():
            if name.startswith('jni/arm64-v8a/') and name.endswith('.so'):
                target = name.replace('jni/', 'lib/', 1)
                if archive.read(target) != aar.read(name):
                    raise ValueError('Packaged OCR engine differs from the pinned AAR: ' + target)
                selected[target] = digest(aar.read(name))
        directory = ROOT / 'assets/licenses/ocr'
        manifest = json.loads((directory / 'manifest.json').read_text())
        for name, entry in manifest.items():
            if digest(archive.read('assets/flutter_assets/assets/licenses/ocr/' + name)) != entry['sha256']:
                raise ValueError('A packaged OCR notice changed: ' + name)
        if archive.read('assets/flutter_assets/assets/licenses/ocr/manifest.json') != (directory / 'manifest.json').read_bytes():
            raise ValueError('The OCR notice registry changed.')
    sdk = Path(os.environ['ANDROID_HOME']) / 'build-tools/36.0.0'
    permissions = subprocess.check_output([sdk / 'aapt2', 'dump', 'permissions', apk], text=True)
    allowed = {
        'android.permission.INTERNET', 'android.permission.ACCESS_NETWORK_STATE',
        'android.permission.WAKE_LOCK', 'android.permission.FOREGROUND_SERVICE',
        'android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK',
        'dev.bookfin.bookfin.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION',
    }
    actual = set(re.findall(r"uses-permission: name='([^']+)'", permissions))
    if not actual <= allowed:
        raise ValueError('Unexpected application permissions: ' + repr(actual - allowed))
    signature = subprocess.check_output([sdk / 'apksigner', 'verify', '--verbose', apk], text=True)
    subprocess.run([sdk / 'zipalign', '-c', '-P', '16', '4', apk], check=True)
    return {'apk': str(apk), 'apkSha256': digest(Path(apk).read_bytes()),
            'modelBytes': 4113088, 'modelSha256': PINS['BOOKFIN_OCR_MODEL'],
            'ocrLibraries': selected, 'native': native, 'permissions': sorted(actual),
            'source': stamp,
            'signature': signature, 'zipAlignmentBytes': 16384}


def sources(output):
    paths = inputs()
    shutil.copyfile(paths['BOOKFIN_OCR_ANDROID_SOURCE'], output / 'Tesseract4Android-4.9.0-source.tar.gz')
    shutil.copyfile(paths['BOOKFIN_OCR_MODEL'], output / 'eng.traineddata')
    shutil.copyfile(paths['BOOKFIN_OCR_MODEL_LICENSE'], output / 'tessdata-fast-4.1.0-LICENSE.txt')
    shutil.copyfile(ROOT / 'docs/ocr-implementation.md', output / 'OCR-BUILD-AND-TERMS.md')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    commands.add_parser('prepare').add_argument('--notices', action='store_true')
    commands.add_parser('verify').add_argument('apk', type=Path)
    args = parser.parse_args()
    if args.command == 'prepare':
        prepare(args.notices)
    else:
        print(json.dumps(verify(args.apk), indent=2))
