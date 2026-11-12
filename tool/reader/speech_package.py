"""Prepare and verify the bundled speech model and the speech library.

The user decided on 2026-11-11 that the speech model ships inside the app
(docs/plans/cross-edition-places.md, "Decision on speech search"). The
model is whisper.cpp's tiny.en at 5 bits (q5_1). The APK stores it
uncompressed, because the speech library reads it in place from the APK.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
from zipfile import ZIP_STORED, ZipFile

ROOT = Path(__file__).resolve().parents[2]

# ggml-tiny.en-q5_1.bin of the ggerganov/whisper.cpp model repository at the
# revision that nix/whisper.nix pins.
PIN = 'c77c5766f1cef09b6b7d47f21b546cbddd4157886b3b5d6d4f709e91e66c7c2b'
ASSET = 'assets/bookfin-speech/tiny.en-q5_1.ggml'
LIBRARY = 'lib/arm64-v8a/libbookfin_speech.so'
BUNDLE = ROOT / '.cache/speech/bundle'
NOTICES = ROOT / 'assets/licenses/speech'


def digest(payload):
    return hashlib.sha256(payload).hexdigest()


def model():
    """The pinned model of the dev shell, after a check of its digest."""
    path = Path(os.environ['BOOKFIN_SPEECH_MODEL'])
    if digest(path.read_bytes()) != PIN:
        raise ValueError('The pinned speech model changed: ' + str(path))
    return path


def prepare(notices=False):
    """Copies the model where the Android build takes its assets, and with
    [notices] writes the license notices of whisper.cpp and the model."""
    destination = BUNDLE / ASSET.removeprefix('assets/')
    destination.parent.mkdir(parents=True, exist_ok=True)
    source = model()
    if not destination.exists() or digest(destination.read_bytes()) != PIN:
        shutil.copyfile(source, destination)
    if notices:
        NOTICES.mkdir(parents=True, exist_ok=True)
        manifest = {}
        payload = (Path(os.environ['BOOKFIN_WHISPER_SOURCE']) / 'LICENSE').read_bytes()
        (NOTICES / 'whisper.cpp.txt').write_bytes(payload)
        manifest['whisper.cpp.txt'] = {'package': 'whisper.cpp 1.9.5 and ggml (MIT)', 'sha256': digest(payload)}
        payload = (
            'Bookfin bundles the English tiny.en model of OpenAI Whisper, which OpenAI\n'
            'released under the MIT License, converted to the ggml format and quantized\n'
            'to 5 bits by the whisper.cpp project (ggml-tiny.en-q5_1.bin).\n'
            'Bookfin transcribes audiobooks on this device only. No audio leaves it.\n'
        ).encode()
        (NOTICES / 'Bookfin-speech-NOTICE.txt').write_bytes(payload)
        manifest['Bookfin-speech-NOTICE.txt'] = {'package': 'Bookfin speech acknowledgements', 'sha256': digest(payload)}
        (NOTICES / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print('Prepared the pinned speech model:', PIN)


def check_model(archive, pin):
    """The size of the speech model in [archive], an open APK. Raises a
    ValueError unless the APK holds exactly one model, the one of [pin],
    stored uncompressed."""
    models = [info for info in archive.infolist() if info.filename.startswith('assets/bookfin-speech/')]
    if not models:
        raise ValueError('The APK holds no speech model: ' + ASSET)
    if [info.filename for info in models] != [ASSET]:
        raise ValueError('The APK must hold only the selected speech model: ' + ASSET)
    info = models[0]
    if digest(archive.read(info)) != pin:
        raise ValueError('The packaged speech model changed.')
    if info.compress_type != ZIP_STORED:
        raise ValueError('The speech model must be stored uncompressed, so that it loads in place.')
    return info.file_size


def verify(apk):
    with ZipFile(apk) as archive:
        size = check_model(archive, PIN)
        library = archive.read(LIBRARY)
        manifest = json.loads((NOTICES / 'manifest.json').read_text())
        for name, entry in manifest.items():
            if digest(archive.read('assets/flutter_assets/assets/licenses/speech/' + name)) != entry['sha256']:
                raise ValueError('A packaged speech notice changed: ' + name)
    return {'apk': str(apk), 'modelAsset': ASSET, 'modelBytes': size, 'modelSha256': PIN,
            'library': LIBRARY, 'libraryBytes': len(library), 'librarySha256': digest(library)}


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
