"""Run the Tesseract layout pass tests on an Android emulator.

This is tool code. It prepares the test pages in a new temporary folder,
serves them to the device on 127.0.0.1 only through `adb reverse`, and runs
integration_test/ocr_layout_test.dart with `flutter test`.

Run it in the dev shell, after `python3 tool/reader/fetch_pdf_corpus.py`:

    python3 tool/reader/ocr_layout_device_test.py emulator-5554

`flutter test` installs a debug build and uninstalls it at the end, so use
only an emulator that belongs to you, never a shared device.
"""

import argparse
import base64
import functools
import http.server
import math
import random
from pathlib import Path
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import zlib

ROOT = Path(__file__).resolve().parents[2]
RAVEN = ROOT / 'tool/research/readers/evidence/text-quality/raven-raster-only.pdf'
CORPUS = ROOT / '.cache/reader-corpus'


def skewed_page(scan, angle, specks, seed):
    """A one-page PDF that draws the image of the one-page PDF [scan] turned
    by [angle] degrees about the page center, with [specks] small black
    squares at random places from [seed] as speck noise."""
    source = scan.read_bytes()
    match = re.search(rb'/Height (\d+) .*?/Width (\d+)\s*>>\s*stream\r?\n(.*?)endstream', source, re.S)
    height, width = int(match.group(1)), int(match.group(2))
    pixels = zlib.decompress(base64.a85decode(match.group(3).strip(), adobe=True))
    if len(pixels) != width * height * 3:
        raise ValueError('The scan is not one RGB image.')
    radians = math.radians(angle)
    cos, sin = math.cos(radians), math.sin(radians)
    # Scale the turned image down so that its corners stay on the page.
    scale = min(width / (width * cos + height * sin), height / (width * sin + height * cos))
    a, b, c, d = width * cos * scale, width * sin * scale, -height * sin * scale, height * cos * scale
    e = width / 2 - (a + c) / 2
    f = height / 2 - (b + d) / 2
    noise = random.Random(seed)
    draw = [f'1 g 0 0 {width} {height} re f', f'q {a:.4f} {b:.4f} {c:.4f} {d:.4f} {e:.4f} {f:.4f} cm /Scan Do Q', '0 g']
    for _ in range(specks):
        size = noise.uniform(0.2, 0.6)
        draw.append(f'{noise.uniform(0, width):.2f} {noise.uniform(0, height):.2f} {size:.2f} {size:.2f} re f')
    content = '\n'.join(draw).encode()
    image = zlib.compress(pixels, 9)
    output = bytearray(b'%PDF-1.4\n')
    offsets = []

    def add(number, value):
        offsets.append(len(output))
        output.extend(f'{number} 0 obj\n'.encode() + value + b'\nendobj\n')

    add(1, b'<< /Type /Catalog /Pages 2 0 R >>')
    add(2, b'<< /Type /Pages /Kids [3 0 R] /Count 1 >>')
    add(3, f'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {width} {height}] /Resources << /XObject << /Scan 4 0 R >> >> /Contents 5 0 R >>'.encode())
    add(4, f'<< /Type /XObject /Subtype /Image /Width {width} /Height {height} /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /FlateDecode /Length {len(image)} >>\nstream\n'.encode() + image + b'\nendstream')
    add(5, f'<< /Length {len(content)} >>\nstream\n'.encode() + content + b'\nendstream')
    xref = len(output)
    output.extend(b'xref\n0 6\n0000000000 65535 f \n')
    for offset in offsets:
        output.extend(f'{offset:010d} 00000 n \n'.encode())
    output.extend(f'trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n'.encode())
    return bytes(output)


def prepare(folder):
    shutil.copyfile(RAVEN, folder / 'scanned.pdf')
    (folder / 'skewed.pdf').write_bytes(skewed_page(RAVEN, 2.5, 300, 20261110))
    for name in ('nist-cloud.pdf', 'census-notice.pdf', 'raven-1873.pdf'):
        shutil.copyfile(CORPUS / name, folder / name)


class Quiet(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *arguments):
        pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('serial', help='the adb serial of your own emulator')
    parser.add_argument('--name', help='run only the tests whose name holds this text')
    arguments = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='bookfin-layout-') as directory:
        folder = Path(directory)
        prepare(folder)
        with socket.socket() as probe:
            probe.bind(('127.0.0.1', 0))
            port = probe.getsockname()[1]
        server = http.server.ThreadingHTTPServer(('127.0.0.1', port), functools.partial(Quiet, directory=directory))
        threading.Thread(target=server.serve_forever, daemon=True).start()
        subprocess.run(['adb', '-s', arguments.serial, 'reverse', f'tcp:{port}', f'tcp:{port}'], check=True)
        try:
            command = ['flutter', 'test', 'integration_test/ocr_layout_test.dart', '-d', arguments.serial,
                       f'--dart-define=BOOKFIN_LAYOUT_PAGES=http://127.0.0.1:{port}']
            if arguments.name:
                command += ['--name', arguments.name]
            result = subprocess.run(command, cwd=ROOT)
        finally:
            subprocess.run(['adb', '-s', arguments.serial, 'reverse', '--remove', f'tcp:{port}'])
            server.shutdown()
    sys.exit(result.returncode)


if __name__ == '__main__':
    main()
