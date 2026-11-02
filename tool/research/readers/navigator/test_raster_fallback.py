import io
from pathlib import Path
import unittest
import zipfile

from raster_fallback import local_raster_wrapper


ROOT = Path(__file__).resolve().parents[4]
BOOK = ROOT / '.cache/navigator/converted/alice.epub'
SVG = 'OEBPS/flow00004.svg'


class RasterFallbackTests(unittest.TestCase):
    def test_converted_kf8_wrapper_resolves_its_own_local_jpeg(self):
        with zipfile.ZipFile(BOOK) as archive:
            result = local_raster_wrapper(archive, SVG)
            self.assertIsNotNone(result)
            self.assertEqual(result['path'], 'OEBPS/resource00000.jpg')
            self.assertEqual(result['mime'], 'image/jpeg')
            self.assertEqual(result['size'], (800, 1104))
            self.assertEqual(result['bytes'], archive.read('OEBPS/resource00000.jpg'))

    def test_active_remote_and_non_wrapper_svg_never_select_a_raster(self):
        with zipfile.ZipFile(BOOK) as archive:
            original = archive.read(SVG).decode()
            variants = {
                'script': original.replace('</svg>', '<script>alert(1)</script></svg>'),
                'event': original.replace('<svg ', '<svg onload="alert(1)" '),
                'remote': original.replace('resource00000.jpg', 'https://invalid.example/cover.jpg'),
                'protocol_relative': original.replace('resource00000.jpg', '//invalid.example/x'),
                'parent_path': original.replace('resource00000.jpg', '../../cover.jpg'),
                'absolute_path': original.replace('resource00000.jpg', '/OEBPS/resource00000.jpg'),
                'file': original.replace('resource00000.jpg', 'file:///tmp/cover.jpg'),
                'data': original.replace('resource00000.jpg', 'data:image/svg+xml,evil'),
                'fragment': original.replace('resource00000.jpg', 'resource00000.jpg#x'),
                'doctype': '<!DOCTYPE svg [<!ENTITY x SYSTEM "file:///etc/passwd">]>' + original,
                'vector': original.replace('</svg>', '<rect width="10" height="10"/></svg>'),
                'style': original.replace('<image ', '<image style="filter:url(https://invalid.example/x)" '),
                'transform': original.replace('<image ', '<image transform="rotate(90)" '),
                'crop': original.replace('viewBox="0 0 800 1104"', 'viewBox="0 0 1 1"'),
            }
            for label, content in variants.items():
                with self.subTest(label=label):
                    output = io.BytesIO()
                    with zipfile.ZipFile(output, 'w') as changed:
                        changed.writestr(SVG, content)
                        changed.writestr('OEBPS/resource00000.jpg', archive.read('OEBPS/resource00000.jpg'))
                    with zipfile.ZipFile(output) as changed:
                        self.assertIsNone(local_raster_wrapper(changed, SVG))

    def test_wrong_raster_dimensions_do_not_silently_change_the_cover(self):
        with zipfile.ZipFile(BOOK) as archive:
            output = io.BytesIO()
            with zipfile.ZipFile(output, 'w') as changed:
                changed.writestr(SVG, archive.read(SVG))
                changed.writestr('OEBPS/resource00000.jpg', (ROOT / 'tool/research/readers/fixtures/dot.png').read_bytes())
            with zipfile.ZipFile(output) as changed:
                self.assertIsNone(local_raster_wrapper(changed, SVG))


if __name__ == '__main__':
    unittest.main()
