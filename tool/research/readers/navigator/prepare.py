import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tarfile
from urllib.parse import urlsplit
import zipfile

from lxml import etree

from raster_fallback import local_raster_wrapper
from semantic_fixture import make_semantic_epub


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
LAB = HERE.parent
WORK = ROOT / '.cache/navigator'
EVIDENCE = LAB / 'evidence/navigator'


def acquire(url, destination, sha256):
    destination.parent.mkdir(parents=True, exist_ok=True)
    if not destination.exists():
        subprocess.run([
            'curl', '--fail', '--location', '--proto', '=https', '--proto-redir', '=https',
            '--connect-timeout', '15', '--max-time', '120', '--max-filesize', '33554432',
            url, '--output', str(destination),
        ], check=True)
    actual = hashlib.sha256(destination.read_bytes()).hexdigest()
    if actual != sha256:
        raise ValueError(f'Hash mismatch: {destination}: {actual}, expected {sha256}')
    print(f'verified {destination.name}: {actual}', flush=True)


def extract_epub(source, destination):
    destination.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(source) as archive:
        if len(archive.namelist()) != len(set(archive.namelist())):
            raise ValueError('Duplicate archive names')
        if sum(entry.file_size for entry in archive.infolist()) > 64000000:
            raise ValueError('Probe expansion limit')
        for entry in archive.infolist():
            target = (destination / entry.filename).resolve()
            if not target.is_relative_to(destination.resolve()):
                raise ValueError('Archive path escapes edition')
        archive.extractall(destination)


def main():
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    sources = json.loads((HERE / 'sources.json').read_text())['sources']
    for source in sources:
        archive = WORK / f'{source["name"]}-{source["version"]}.tar.gz'
        acquire(source['url'], archive, source['sha256'])
        destination = WORK / 'sources' / source['name']
        if destination.exists():
            shutil.rmtree(destination)
        destination.mkdir(parents=True)
        with tarfile.open(archive) as package:
            package.extractall(destination, filter='data')
        if source.get('strip_components'):
            inner = next(destination.iterdir())
            for item in inner.iterdir():
                shutil.move(item, destination / item.name)
            inner.rmdir()
    corpus = json.loads((LAB / 'corpus-manifest.json').read_text())['samples']
    samples = [entry for entry in corpus if entry['format'] in ('epub', 'mobi')]
    books = []
    for sample in samples:
        path = WORK / 'inputs' / sample['filename']
        acquire(sample['url'], path, sample['sha256'])
        books.append((sample['id'], path, sample['expected_phrases'][0]))
    for name in ['river', 'mobi6-plain', 'mobi6-palmdoc', 'pg11-kf8']:
        suffix = '.epub' if name == 'river' else '.mobi'
        destination = WORK / 'inputs' / (name + suffix)
        shutil.copyfile(LAB / 'fixtures' / (name + suffix), destination)
        books.append((name, destination, 'Alice' if name == 'pg11-kf8' else 'The river follows the old road.'))
    semantic = WORK / 'inputs/semantic.epub'
    make_semantic_epub(semantic, ROOT)
    books.append(('semantic-epub3', semantic, 'Édition stable'))
    converted = WORK / 'converted'
    converted.mkdir(exist_ok=True)
    observations = []
    for name, source, phrase in books:
        if source.suffix == '.mobi':
            subprocess.run(['mobitool', '-e', '-o', str(converted), str(source)], check=True)
            epub = converted / (source.stem + '.epub')
        else:
            epub = source
        if name == 'pg11-kf8':
            shutil.copyfile(epub, converted / 'alice.epub')
        target = WORK / 'unpacked' / name
        if target.exists():
            shutil.rmtree(target)
        extract_epub(epub, target)
        observations.append({
            'id': name, 'epub': str(epub.relative_to(ROOT)),
            'directory': str(target.relative_to(ROOT)), 'phrase': phrase,
            'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
            'epub_sha256': hashlib.sha256(epub.read_bytes()).hexdigest(),
        })
    assets = WORK / 'widget-assets'
    assets.mkdir(exist_ok=True)
    with zipfile.ZipFile(converted / 'alice.epub') as archive:
        svg_path = 'OEBPS/flow00004.svg'
        fallback = local_raster_wrapper(archive, svg_path)
        if fallback is None:
            raise ValueError('Expected real KF8 wrapper no longer matches bounded fallback')
        (assets / 'kf8-original.svg').write_bytes(archive.read(svg_path))
        (assets / 'kf8-cover.jpg').write_bytes(fallback['bytes'])
        root = etree.fromstring(archive.read('OEBPS/part00000.html'))
        svg_links = root.xpath('//@*[local-name()="href" or local-name()="src"]')
        if not any(urlsplit(href).path == 'flow00004.svg' for href in svg_links):
            raise ValueError('The cover document does not refer to the expected SVG')
        fallback_evidence = {
            'document': 'OEBPS/part00000.html', 'svg': svg_path,
            'svg_bytes': len(archive.read(svg_path)), 'raster': fallback['path'],
            'raster_mime': fallback['mime'], 'raster_size': list(fallback['size']),
            'raster_sha256': hashlib.sha256(fallback['bytes']).hexdigest(),
            'policy': 'Only exact local single-raster SVG wrappers; otherwise explicit unsupported-image fallback. No SVG code executes.',
        }
    shutil.copyfile(LAB / 'fixtures/dot.png', assets / 'dot.png')
    (WORK / 'books.json').write_text(json.dumps(observations, indent=2) + '\n')
    (EVIDENCE / 'resource-associations.json').write_text(json.dumps(fallback_evidence, indent=2) + '\n')
    scripts = WORK / 'sources/flutter_epub_viewer/lib/assets/webpage'
    hashes = {str(path.relative_to(scripts)): hashlib.sha256(path.read_bytes()).hexdigest()
              for path in scripts.rglob('*') if path.is_file()}
    (EVIDENCE / 'bundled-web-assets.json').write_text(json.dumps(hashes, indent=2, sort_keys=True) + '\n')
    upstream = (WORK / 'sources/epubjs/dist/epub.js').read_bytes()
    bundled = (scripts / 'dist/epub.js').read_bytes()
    provenance = {
        'upstream_archive_sha256': next(source['sha256'] for source in sources if source['name'] == 'epubjs'),
        'upstream_dist_sha256': hashlib.sha256(upstream).hexdigest(),
        'bundled_dist_sha256': hashlib.sha256(bundled).hexdigest(),
        'byte_identical': upstream == bundled,
        'identical_after_newline_normalization': upstream.replace(b'\r\n', b'\n') == bundled.replace(b'\r\n', b'\n'),
    }
    (EVIDENCE / 'epubjs-provenance.json').write_text(json.dumps(provenance, indent=2) + '\n')
    print(f'Prepared {len(observations)} EPUB editions; no standalone HTML/Markdown inputs.')


if __name__ == '__main__':
    main()
