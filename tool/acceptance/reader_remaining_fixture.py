import sys
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tool/research/readers/navigator'))
from semantic_fixture import make_semantic_epub


def make_remaining_epub(destination, jpeg):
    make_semantic_epub(destination, ROOT)
    with zipfile.ZipFile(destination) as archive:
        entries = {name: archive.read(name) for name in archive.namelist()}
    wrapper = '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="100%" height="100%" viewBox="0 0 2 3" preserveAspectRatio="xMidYMid meet"><image width="2" height="3" xlink:href="square.jpg"/></svg>'
    entries['OEBPS/Images/square.jpg'] = jpeg
    entries['OEBPS/Images/wrapper.svg'] = wrapper.encode()
    entries['OEBPS/Images/active.svg'] = wrapper.replace('<svg ', '<svg onload="fetch(\'http://127.0.0.1:7365/probe/svg\')" ').encode()
    assets = '<h1 id="heading">Asset checks</h1><p>Local PNG <img src="../Images/dot.png" alt="Local PNG sepia square"/></p><p>Local JPEG <img src="../Images/square.jpg" alt="Local JPEG sepia rectangle"/></p><p>Exact JPEG wrapper <img src="../Images/wrapper.svg" alt="Exact JPEG wrapper rectangle"/></p><p>Active SVG <img src="../Images/active.svg" alt="Active SVG blocked marker"/></p><p>Embedded font association: ffi WMW iii.</p><p><a href="reflow.xhtml#heading">Visit reflow checks</a></p>'
    denial = '''<h1 id="heading">Admission checks</h1><p>Readable text remains after unsafe content is removed.</p><script>fetch('http://127.0.0.1:7365/probe/script');navigator.mediaDevices.getUserMedia({audio:true,video:true});navigator.geolocation.getCurrentPosition(()=>{});</script><iframe src="http://127.0.0.1:7365/probe/frame"></iframe><img src="http://127.0.0.1:7365/probe/image" alt="Remote image blocked marker"/><form action="http://127.0.0.1:7365/probe/form"><input name="synthetic"/><button>Submit blocked form</button></form><p><a href="http://127.0.0.1:7365/probe/navigation">Remote link blocked marker</a></p><p><a href="javascript:alert(1)">Active link blocked marker</a></p><p><a href="reflow.xhtml#heading">Visit reflow checks</a></p>'''
    reflow = '<h1 id="heading">Reflow checks</h1><p>Select this sentence to check native text selection.</p><p><a href="one.xhtml#heading">Return to asset checks</a></p>' + ''.join(f'<p>Reflow passage {number}. The quiet harbour keeps its place while the letters grow. A reader follows these words in their written order without a network connection.</p>' for number in range(1, 21))
    for name, body in [('one', assets), ('denial', denial), ('reflow', reflow)]:
        entries[f'OEBPS/Text/{name}.xhtml'] = f'<html xmlns="http://www.w3.org/1999/xhtml" lang="en"><head><title>{name}</title><link rel="stylesheet" href="../Styles/book.css"/></head><body>{body}</body></html>'.encode()
    entries.pop('OEBPS/Text/two.xhtml')
    entries['OEBPS/Styles/book.css'] += b'img{width:48px;height:48px}p{line-height:1.3}'
    entries['OEBPS/Styles/denial.css'] = b'@import url("http://127.0.0.1:7365/probe/css");'
    entries['OEBPS/Text/denial.xhtml'] = entries['OEBPS/Text/denial.xhtml'].replace(b'</head>', b'<link rel="stylesheet" href="../Styles/denial.css"/></head>')
    entries['OEBPS/nav.xhtml'] = ('<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>Contents</title></head><body><nav epub:type="toc"><ol>' + ''.join(f'<li><a href="Text/{name}.xhtml#heading">{label}</a></li>' for name, label in [('one', 'Asset checks'), ('denial', 'Admission checks'), ('reflow', 'Reflow checks')]) + '</ol></nav></body></html>').encode()
    package = entries['OEBPS/book.opf'].decode()
    package = package.replace('<item id="two" href="Text/two.xhtml" media-type="application/xhtml+xml"/>', '')
    package = package.replace('</manifest>', '<item id="denial" href="Text/denial.xhtml" media-type="application/xhtml+xml"/><item id="reflow" href="Text/reflow.xhtml" media-type="application/xhtml+xml"/><item id="jpg" href="Images/square.jpg" media-type="image/jpeg"/><item id="wrapper" href="Images/wrapper.svg" media-type="image/svg+xml"/><item id="active" href="Images/active.svg" media-type="image/svg+xml"/></manifest>')
    package = package.replace('</manifest>', '<item id="denial-css" href="Styles/denial.css" media-type="text/css"/></manifest>')
    package = package.replace('<itemref idref="two"/>', '<itemref idref="denial"/><itemref idref="reflow"/>')
    entries['OEBPS/book.opf'] = package.encode()
    with zipfile.ZipFile(destination, 'w') as archive:
        for name, content in entries.items():
            archive.writestr(zipfile.ZipInfo(name, (2026, 11, 2, 0, 0, 0)), content)


if __name__ == '__main__':
    make_remaining_epub(Path(sys.argv[1]), Path(sys.argv[2]).read_bytes())
