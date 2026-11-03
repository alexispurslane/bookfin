import hashlib
import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import sys
import time
from urllib.parse import urlencode
import zlib


ROOT = Path.cwd()
OUTPUT = Path(__file__).resolve().parent
PRIVATE = ROOT / '.cache/remaining-acceptance'
sys.path.insert(0, str(ROOT / 'tool/research/plugin'))
import dedicated_fixture
from fixture import private_json


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def scan_pdf(destination, blank=False):
    image = ROOT / 'test/reader/fixtures/ocr/generated-english.png'
    rgb = subprocess.check_output(['ffmpeg', '-v', 'error', '-nostdin', '-i', str(image), '-frames:v', '1', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-threads', '1', '-'])
    pixels = zlib.compress(rgb)
    output = bytearray(b'%PDF-1.4\n')
    offsets = [0]
    def add(number, value):
        offsets.append(len(output))
        output.extend(f'{number} 0 obj\n'.encode() + value + b'\nendobj\n')
    add(1, b'<< /Type /Catalog /Pages 2 0 R >>')
    add(2, b'<< /Type /Pages /Kids [3 0 R 6 0 R] /Count 2 >>')
    add(3, b'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 1600 4000] /Resources << /XObject << /Scan 4 0 R >> >> /Contents 5 0 R >>')
    add(4, f'<< /Type /XObject /Subtype /Image /Width 1400 /Height 600 /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /FlateDecode /Length {len(pixels)} >>\nstream\n'.encode() + pixels + b'\nendstream')
    draw = b'' if blank else '\n'.join(f'q 800 0 0 343 {column * 800} {row * 343} cm /Scan Do Q' for row in range(11) for column in range(2)).encode()
    add(5, f'<< /Length {len(draw)} >>\nstream\n'.encode() + draw + b'\nendstream')
    add(6, b'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 1600 4000] /Resources << /XObject << /Scan 4 0 R >> >> /Contents 7 0 R >>')
    add(7, b'<< /Length 0 >>\nstream\n\nendstream')
    xref = len(output)
    output.extend(b'xref\n0 8\n0000000000 65535 f \n')
    for offset in offsets[1:]:
        output.extend(f'{offset:010d} 00000 n \n'.encode())
    output.extend(f'trailer\n<< /Size 8 /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n'.encode())
    destination.write_bytes(output)


os.umask(0o077)
PRIVATE.mkdir(parents=True, exist_ok=True)
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
    scan_pdf(media / 'Acceptance dense English.pdf')
    scan_pdf(media / 'Acceptance blank.pdf', blank=True)
    server.start()
    server.seed()
    admin = server.api('admin')
    admin.json('POST', '/Library/VirtualFolders?' + urlencode({'name': 'Remaining acceptance scans', 'collectionType': 'books', 'refreshLibrary': 'false'}), {'LibraryOptions': {'PathInfos': [{'Path': str(media)}], 'EnableRealtimeMonitor': False, 'EnableInternetProviders': False, 'EnableEmbeddedTitles': False, 'AutomaticRefreshIntervalDays': 0}})
    library = next(item for item in admin.json('GET', '/Library/VirtualFolders') if item['Name'] == 'Remaining acceptance scans')
    for name in ('alice', 'bob'):
        policy = admin.json('GET', f'/Users/{server.accounts[name]["id"]}')['Policy']
        policy.update(IsAdministrator=False, EnableAllFolders=False, EnabledFolders=[library['ItemId']], EnableContentDownloading=True, EnableContentDeletion=False)
        admin.json('POST', f'/Users/{server.accounts[name]["id"]}/Policy', policy)
    admin.json('POST', '/Library/Refresh')
    deadline = time.monotonic() + 90
    while time.monotonic() < deadline:
        items = server.api('alice').json('GET', f'/Users/{server.accounts["alice"]["id"]}/Items?recursive=true&includeItemTypes=Book')['Items']
        if len(items) == 2:
            break
        time.sleep(0.5)
    else:
        raise RuntimeError('Two ordinary PDF originals did not scan')
    private_json(PRIVATE / 'owned-server.json', {'root': str(server.root), 'controllerPid': os.getpid(), 'serverPid': server.process.pid, 'serverId': server.server_id})
    manifest = {'pluginSha256': digest(plugin), 'imageSha256': digest(ROOT / 'test/reader/fixtures/ocr/generated-english.png'), 'densePage': {'widthPoints': 1600, 'heightPoints': 4000, 'imageDraws': 22, 'referenceWords': 814}, 'secondPage': 'Genuinely blank, zero drawing commands and no text layer', 'files': {path.name: {'bytes': path.stat().st_size, 'sha256': digest(path)} for path in media.iterdir()}}
    (OUTPUT / 'corpus.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print('Owned ordinary fixture ready; generated credentials remain private.', flush=True)
    while not stop:
        time.sleep(0.5)
finally:
    server.stop()
    print('Owned fixture stopped; private recovery data retained for audit.', flush=True)
