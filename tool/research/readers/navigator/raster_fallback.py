import io
from pathlib import PurePosixPath
from urllib.parse import urlsplit

from lxml import etree
from PIL import Image, UnidentifiedImageError


def local_raster_wrapper(archive, svg_path):
    if len(archive.namelist()) != len(set(archive.namelist())):
        return None
    try:
        if archive.getinfo(svg_path).file_size > 8192:
            return None
        source = archive.read(svg_path)
        parser = etree.XMLParser(resolve_entities=False, no_network=True)
        root = etree.fromstring(source, parser)
        if root.getroottree().docinfo.doctype or root.getprevious() is not None:
            return None
        if root.tag != '{http://www.w3.org/2000/svg}svg' or len(root) != 1:
            return None
        if set(root.attrib) - {'height', 'width', 'viewBox', 'version', 'preserveAspectRatio', 'class'}:
            return None
        if root.get('width') != '100%' or root.get('height') != '100%':
            return None
        if root.get('preserveAspectRatio') != 'xMidYMid meet':
            return None
        image = root[0]
        if image.tag != '{http://www.w3.org/2000/svg}image' or len(image):
            return None
        href_key = '{http://www.w3.org/1999/xlink}href'
        if set(image.attrib) != {'width', 'height', href_key}:
            return None
        if any((text or '').strip() for text in [root.text, image.text, image.tail]):
            return None
        width, height = int(image.get('width')), int(image.get('height'))
        if width < 1 or height < 1 or width * height > 16000000:
            return None
        if root.get('viewBox') != f'0 0 {width} {height}':
            return None
        href = image.get(href_key)
        url = urlsplit(href)
        path = PurePosixPath(href)
        if url.scheme or url.netloc or url.query or url.fragment:
            return None
        if path.is_absolute() or '..' in path.parts or '%' in href or '\\' in href:
            return None
        raster_path = str(PurePosixPath(svg_path).parent / path)
        entry = archive.getinfo(raster_path)
        if entry.file_size > 16000000:
            return None
        content = archive.read(raster_path)
        with Image.open(io.BytesIO(content)) as raster:
            mime = {'JPEG': 'image/jpeg', 'PNG': 'image/png'}.get(raster.format)
            if mime is None or raster.size != (width, height):
                return None
            raster.verify()
        return {'path': raster_path, 'mime': mime, 'size': (width, height), 'bytes': content}
    except (etree.XMLSyntaxError, KeyError, ValueError, UnidentifiedImageError, OSError):
        return None
