import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import socket
import subprocess
import sys
import time
from urllib.parse import urlencode
import zlib


ROOT = Path.cwd()
OUTPUT = Path(__file__).resolve().parent
PRIVATE = ROOT / '.cache/combined-acceptance'
sys.path.insert(0, str(ROOT / 'tool/research/plugin'))
import dedicated_fixture
from fixture import private_json


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def scan_pdf(image, destination, repetitions=1):
    info = json.loads(subprocess.check_output(['ffprobe', '-v', 'error', '-show_streams', '-of', 'json', str(image)]))['streams'][0]
    width, height = info['width'], info['height']
    rgb = subprocess.check_output(['ffmpeg', '-v', 'error', '-nostdin', '-i', str(image), '-frames:v', '1', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-threads', '1', '-'])
    pixels = zlib.compress(rgb)
    output = bytearray(b'%PDF-1.4\n')
    offsets = [0]
    def object_bytes(number, value):
        offsets.append(len(output))
        output.extend(f'{number} 0 obj\n'.encode() + value + b'\nendobj\n')
    object_bytes(1, b'<< /Type /Catalog /Pages 2 0 R >>')
    object_bytes(2, b'<< /Type /Pages /Kids [3 0 R] /Count 1 >>')
    object_bytes(3, f'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {width} {height * repetitions}] /Resources << /XObject << /Scan 4 0 R >> >> /Contents 5 0 R >>'.encode())
    object_bytes(4, f'<< /Type /XObject /Subtype /Image /Width {width} /Height {height} /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /FlateDecode /Length {len(pixels)} >>\nstream\n'.encode() + pixels + b'\nendstream')
    draw = '\n'.join(f'q {width} 0 0 {height} 0 {height * index} cm /Scan Do Q' for index in range(repetitions)).encode()
    object_bytes(5, f'<< /Length {len(draw)} >>\nstream\n'.encode() + draw + b'\nendstream')
    xref = len(output)
    output.extend(b'xref\n0 6\n0000000000 65535 f \n')
    for offset in offsets[1:]:
        output.extend(f'{offset:010d} 00000 n \n'.encode())
    output.extend(f'trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n'.encode())
    destination.write_bytes(output)


os.umask(0o077)
for port in (7364, 7365):
    with socket.socket() as listener:
        listener.bind(('127.0.0.1', port))
plugin = Path('/Users/alexispurslane/.t3/worktrees/bookfin/t3-2ef60719/.cache/plugin/package/Bookfin.Storage_0.1.1.0.zip')
assert digest(plugin) == '3b0de5ca1df39baf67c786079898b1ee3b0b09d3bdb86d00ece8a7f5731a9105'
dedicated_fixture.ORIGIN = 'http://127.0.0.1:7364'
server = dedicated_fixture.Server(plugin)
network = server.root / 'config/network.xml'
network.write_text(network.read_text().replace('7464', '7364').replace('7465', '7365'))
private_json(PRIVATE / 'owned-server.json', {'root': str(server.root), 'controllerPid': os.getpid()})
stop = False
def stop_requested(*arguments):
    global stop
    stop = True
signal.signal(signal.SIGTERM, stop_requested)
signal.signal(signal.SIGINT, stop_requested)
try:
    media = server.root / 'media'
    media.mkdir()
    image = ROOT / 'test/reader/fixtures/ocr/generated-english.png'
    assert digest(image) == '30fce43633b99aa18db29680ee9ed9ebd1733c97eca7ee6c3055eaeddd1d6af6'
    scan_pdf(image, media / 'English scan.pdf')
    crop = Path('/Users/alexispurslane/.t3/worktrees/bookfin/t3-66d8fead/.cache/ocr-android-renewed/scans/raven-1873-page-9-poem-crop.png')
    crop_hash = digest(crop)
    scan_pdf(crop, media / 'Historical scan.pdf')
    for source, title in [('pg11-kf8.mobi', 'Alice KF8.mobi'), ('simple.pdf', 'Ordinary PDF.pdf'), ('scanned.pdf', 'Empty scan.pdf')]:
        shutil.copyfile(ROOT / 'tool/research/readers/fixtures' / source, media / title)
    assert digest(media / 'Alice KF8.mobi') == 'd8211269aed55ded8302f289950936db8368b4d4d384c463b722034152f8f1d2'
    server.start()
    server.seed()
    admin = server.api('admin')
    admin.json('POST', '/Library/VirtualFolders?' + urlencode({'name': 'Owned acceptance books', 'collectionType': 'books', 'refreshLibrary': 'false'}), {'LibraryOptions': {
        'PathInfos': [{'Path': str(media)}], 'EnableRealtimeMonitor': False,
        'EnableInternetProviders': False, 'EnableEmbeddedTitles': False, 'AutomaticRefreshIntervalDays': 0}})
    libraries = admin.json('GET', '/Library/VirtualFolders')
    library = next(item for item in libraries if item['Name'] == 'Owned acceptance books')
    policy = admin.json('GET', f'/Users/{server.accounts["alice"]["id"]}')['Policy']
    policy.update(IsAdministrator=False, EnableAllFolders=False, EnabledFolders=[library['ItemId']], EnableContentDownloading=True, EnableContentDeletion=False)
    admin.json('POST', f'/Users/{server.accounts["alice"]["id"]}/Policy', policy)
    admin.json('POST', '/Library/Refresh')
    deadline = time.monotonic() + 90
    while time.monotonic() < deadline:
        items = server.api('alice').json('GET', f'/Users/{server.accounts["alice"]["id"]}/Items?recursive=true&includeItemTypes=Book')['Items']
        if len(items) == 5:
            break
        time.sleep(0.5)
    else:
        raise RuntimeError('Five ordinary originals did not scan')
    details = [server.api('alice').json('GET', f'/Users/{server.accounts["alice"]["id"]}/Items/{item["Id"]}') for item in items]
    (OUTPUT / 'ordinary-book-dtos.json').write_text(json.dumps(details, indent=2) + '\n')
    manifest = {'serverVersion': '12.4.0', 'pluginSha256': digest(plugin), 'ordinaryBooks': len(items),
                'allOmitContainerAndMediaSources': all('Container' not in item and 'MediaSources' not in item for item in details),
                'generatedImageSha256': digest(image), 'historicalCropSha256': crop_hash,
                'files': {path.name: {'bytes': path.stat().st_size, 'sha256': digest(path)} for path in media.iterdir()}}
    (OUTPUT / 'corpus.json').write_text(json.dumps(manifest, indent=2) + '\n')
    private_json(PRIVATE / 'owned-server.json', {'root': str(server.root), 'controllerPid': os.getpid(), 'serverId': server.server_id})
    print('Owned ordinary fixture ready; credentials are private.', flush=True)
    while not stop:
        time.sleep(0.5)
finally:
    server.stop()
    print('Owned fixture STOPPED; private recovery data retained pending audit.', flush=True)
