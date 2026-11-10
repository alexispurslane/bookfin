"""Wrap one JPEG scan, byte for byte, as the only image of a one-page PDF.

This is tool code. It made test/reader/fixtures/reflow/footnote-page.pdf:

    python3 tool/reader/jpeg_page_pdf.py page.jpg footnote-page.pdf 500

The page is the image's size at the given pixels per inch. The PDF has no
text layer, so Bookfin recognizes the page.
"""

import argparse
from pathlib import Path
import struct


def jpeg_size(data):
    """The width, the height and the color components of the JPEG [data]."""
    index = 2
    while index + 9 < len(data):
        marker = data[index + 1]
        length = struct.unpack('>H', data[index + 2:index + 4])[0]
        if 0xC0 <= marker <= 0xCF and marker not in (0xC4, 0xC8, 0xCC):
            height, width = struct.unpack('>HH', data[index + 5:index + 9])
            return width, height, data[index + 9]
        index += 2 + length
    raise ValueError('The file has no JPEG frame header.')


def jpeg_page(jpeg, ppi):
    """A one-page PDF that draws the JPEG [jpeg] over the whole page."""
    width, height, components = jpeg_size(jpeg)
    space = {1: '/DeviceGray', 3: '/DeviceRGB'}[components]
    points = (width * 72 / ppi, height * 72 / ppi)
    content = f'q {points[0]:.2f} 0 0 {points[1]:.2f} 0 0 cm /Scan Do Q'.encode()
    output = bytearray(b'%PDF-1.4\n')
    offsets = []

    def add(number, value):
        offsets.append(len(output))
        output.extend(f'{number} 0 obj\n'.encode() + value + b'\nendobj\n')

    add(1, b'<< /Type /Catalog /Pages 2 0 R >>')
    add(2, b'<< /Type /Pages /Kids [3 0 R] /Count 1 >>')
    add(3, f'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {points[0]:.2f} {points[1]:.2f}] '
           f'/Resources << /XObject << /Scan 4 0 R >> >> /Contents 5 0 R >>'.encode())
    add(4, f'<< /Type /XObject /Subtype /Image /Width {width} /Height {height} /ColorSpace {space} '
           f'/BitsPerComponent 8 /Filter /DCTDecode /Length {len(jpeg)} >>\nstream\n'.encode()
        + jpeg + b'\nendstream')
    add(5, f'<< /Length {len(content)} >>\nstream\n'.encode() + content + b'\nendstream')
    xref = len(output)
    output.extend(b'xref\n0 6\n0000000000 65535 f \n')
    for offset in offsets:
        output.extend(f'{offset:010d} 00000 n \n'.encode())
    output.extend(f'trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n'.encode())
    return bytes(output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('jpeg', type=Path, help='the scanned page')
    parser.add_argument('pdf', type=Path, help='the PDF to write')
    parser.add_argument('ppi', type=float, help='the pixels per inch of the scan')
    arguments = parser.parse_args()
    arguments.pdf.write_bytes(jpeg_page(arguments.jpeg.read_bytes(), arguments.ppi))


if __name__ == '__main__':
    main()
