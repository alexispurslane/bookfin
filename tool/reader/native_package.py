import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
from zipfile import ZipFile
import ocr_package


ROOT = Path(__file__).resolve().parents[2]


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def prepare():
    ocr_package.prepare()
    source = Path(os.environ['BOOKFIN_PDFIUM_ANDROID']) / 'lib/libpdfium.so'
    destination = ROOT / '.dart_tool/hooks_runner/shared/pdfium_dart/build/chromium_8125/android-arm64/libpdfium.so'
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, destination)
    print('Prepared pinned PDFium chromium/8125 Android ARM64 library:', digest(source))


def verify(apk):
    directory = ROOT / 'assets/licenses/reader'
    manifest = json.loads((directory / 'manifest.json').read_text())
    with ZipFile(apk) as archive:
        for name, notice in manifest.items():
            payload = archive.read('assets/flutter_assets/assets/licenses/reader/' + name)
            if hashlib.sha256(payload).hexdigest() != notice['sha256']:
                raise ValueError('Packaged native notice differs from its pinned source: ' + name)
        expected = digest(Path(os.environ['BOOKFIN_PDFIUM_ANDROID']) / 'lib/libpdfium.so')
        if hashlib.sha256(archive.read('lib/arm64-v8a/libpdfium.so')).hexdigest() != expected:
            raise ValueError('Packaged PDFium differs from the pinned Android archive.')
        for name in ['libbookfin_mobi.so', 'libmobi.so']:
            if len(archive.read('lib/arm64-v8a/' + name)) < 4096:
                raise ValueError('Missing native reader library: ' + name)
    print(json.dumps({'apk': str(apk), 'sha256': digest(apk), 'noticeFiles': len(manifest), 'pdfiumSha256': expected}, indent=2))


def sources(output):
    if subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT).strip():
        raise ValueError('Commit the complete candidate before exporting its matching source.')
    output.mkdir(parents=True, exist_ok=False)
    revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    subprocess.run(['git', 'archive', '--format=tar', '--output=' + str(output / 'bookfin-source.tar'), revision], cwd=ROOT, check=True)
    with tarfile.open(output / 'libmobi-0.12-source.tar.gz', 'w:gz') as archive:
        archive.add(os.environ['BOOKFIN_LIBMOBI_SOURCE'], arcname='libmobi-0.12')
    shutil.copyfile(os.environ['BOOKFIN_GPL3_TEXT'], output / 'GPL-3.0.txt')
    shutil.copyfile(Path(os.environ['BOOKFIN_LIBMOBI_SOURCE']) / 'COPYING', output / 'LGPL-3.0.txt')
    shutil.copyfile(ROOT / 'docs/research/native-reader-packaging.md', output / 'BUILD-AND-INSTALL.md')
    ocr_package.sources(output)
    inventory = {path.name: digest(path) for path in output.iterdir() if path.is_file()}
    (output / 'manifest.json').write_text(json.dumps({'sourceCommit': revision, 'files': inventory}, indent=2) + '\n')
    print(json.dumps({'sourceCommit': revision, 'directory': str(output), 'files': inventory}, indent=2))


def main():
    parser = argparse.ArgumentParser()
    commands = parser.add_subparsers(dest='command', required=True)
    commands.add_parser('prepare')
    commands.add_parser('verify').add_argument('apk', type=Path)
    commands.add_parser('sources').add_argument('output', type=Path)
    args = parser.parse_args()
    if args.command == 'prepare':
        prepare()
    elif args.command == 'verify':
        verify(args.apk)
    else:
        sources(args.output.resolve())


if __name__ == '__main__':
    main()
