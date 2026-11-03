import hashlib
import json
import os
from pathlib import Path
import shutil


ROOT = Path(__file__).resolve().parents[2]


def main():
    source = Path(os.environ['BOOKFIN_LIBMOBI_SOURCE'])
    pdfium = Path(os.environ['BOOKFIN_PDFIUM_ANDROID'])
    output = ROOT / 'assets/licenses/reader'
    output.mkdir(parents=True, exist_ok=True)
    notices = {}

    def keep(name, path, package):
        destination = output / name
        shutil.copyfile(path, destination)
        notices[name] = {'package': package, 'sha256': hashlib.sha256(destination.read_bytes()).hexdigest()}

    package = 'libmobi 0.12 and Bookfin converter (LGPL-3.0-or-later)'
    keep('Bookfin-native-NOTICE.txt', ROOT / 'native/NOTICE.txt', package)
    keep('LGPL-3.0.txt', source / 'COPYING', package)
    keep('GPL-3.0.txt', Path(os.environ['BOOKFIN_GPL3_TEXT']), package)
    for name in ['tools/mobitool.c', 'tools/common.c', 'src/xmlwriter.c']:
        text = (source / name).read_bytes().split(b'*/', 1)[0] + b'*/\n'
        filename = name.replace('/', '-') + '-notice.txt'
        (output / filename).write_bytes(text)
        notices[filename] = {'package': package, 'sha256': hashlib.sha256(text).hexdigest()}
    miniz = (source / 'src/miniz.c').read_bytes()
    text = miniz[miniz.rindex(b'/*'):]
    (output / 'miniz-notice.txt').write_bytes(text)
    notices['miniz-notice.txt'] = {'package': 'miniz 1.15', 'sha256': hashlib.sha256(text).hexdigest()}
    keep('PDFium-LICENSE.txt', pdfium / 'LICENSE', 'PDFium chromium/8125')
    for path in sorted((pdfium / 'licenses').iterdir()):
        if path.is_file():
            keep('PDFium-' + path.name, path, 'PDFium chromium/8125: ' + path.stem)
    (output / 'manifest.json').write_text(json.dumps(notices, indent=2, sort_keys=True) + '\n')
    print(f'Prepared {len(notices)} native notices from pinned source inputs.')


if __name__ == '__main__':
    main()
