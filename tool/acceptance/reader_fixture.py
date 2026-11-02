import io
from pathlib import Path
import subprocess
import sys
import zipfile


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tool/research/readers/navigator'))
from semantic_fixture import make_semantic_epub


def prepare():
    destination = ROOT / '.cache/sync/runtime/media/public/Work/Text Edition/Synthetic Work.epub'
    if not destination.exists():
        raise RuntimeError('Seed this checkout disposable Jellyfin before preparing the reader fixture')
    make_semantic_epub(destination, ROOT)
    with zipfile.ZipFile(destination) as archive:
        entries = {name: archive.read(name) for name in archive.namelist()}
    package = entries['OEBPS/book.opf'].decode().replace('Semantic probe', 'Synthetic Work').replace('<dc:language>fr', '<dc:language>en')
    package = package.replace('</manifest>', '<item id="jpeg" href="Images/square.jpg" media-type="image/jpeg"/></manifest>')
    entries['OEBPS/book.opf'] = package
    entries['OEBPS/nav.xhtml'] = '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>Contents</title></head><body><nav epub:type="toc"><ol><li><a href="Text/one.xhtml#heading">The quiet harbour</a></li><li><a href="Text/two.xhtml#note">The lantern room</a></li></ol></nav></body></html>'
    opening = '<h1 id="heading">The quiet harbour</h1><p>This book was written for a disposable Bookfin reading test. No private library or published story is used.</p><p>Morning light filled the quiet harbour. Mira carried a lantern to the old reading room, where every shelf held a different journey.</p><p>The sepia square below is a local PNG image.</p><img src="../Images/dot.png" alt="A sepia PNG square"/><p>The next square is a local JPEG image.</p><img src="../Images/square.jpg" alt="A sepia JPEG square"/><p><a href="two.xhtml#note">Visit the lantern room</a></p>'
    paragraphs = ''.join(f'<p>Harbour passage {number}. The reader followed the shoreline and watched the small boats return. A bookmark could keep this place while the room grew dark.</p>' for number in range(1, 17))
    ending = '<h1 id="note">The lantern room</h1><p>The amber lantern rested beside an open book. This distinct sentence is the destination for the search word starfish.</p><p><a href="one.xhtml#heading">Return to the quiet harbour</a></p><p>Reading continued without a connection. The book, pictures, and typeface belonged to the downloaded edition.</p>'
    for name, content in [('one', opening + paragraphs), ('two', ending + paragraphs)]:
        entries[f'OEBPS/Text/{name}.xhtml'] = f'<html xmlns="http://www.w3.org/1999/xhtml" lang="en"><head><title>{name}</title><link rel="stylesheet" href="../Styles/book.css"/></head><body>{content}</body></html>'
    entries['OEBPS/Styles/book.css'] += b'img{width:96px;height:96px}p{line-height:1.5}'
    entries['OEBPS/Images/square.jpg'] = subprocess.check_output(['ffmpeg', '-v', 'error', '-nostdin', '-i', str(ROOT / 'tool/research/readers/fixtures/dot.png'), '-frames:v', '1', '-f', 'image2pipe', '-vcodec', 'mjpeg', '-threads', '1', '-'])
    output = io.BytesIO()
    with zipfile.ZipFile(output, 'w') as archive:
        for name, content in entries.items():
            archive.writestr(zipfile.ZipInfo(name, (2026, 11, 2, 0, 0, 0)), content)
    destination.write_bytes(output.getvalue())
    print('Prepared synthetic two-chapter EPUB with local PNG, JPEG, and Source Serif 4')


if __name__ == '__main__':
    prepare()
