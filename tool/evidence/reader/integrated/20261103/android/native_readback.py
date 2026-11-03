import hashlib
import io
import json
from pathlib import Path
import struct
import subprocess
import zipfile


def adb(*arguments):
    return subprocess.check_output(['adb', '-s', 'emulator-5554', *arguments])


package = adb('shell', 'pm', 'path', 'dev.bookfin.bookfin').decode().strip().removeprefix('package:')
installed = adb('exec-out', 'cat', package)
process = adb('shell', 'pidof', 'dev.bookfin.bookfin').decode().split()[0]
maps = adb('exec-out', 'run-as', 'dev.bookfin.bookfin', 'cat', f'/proc/{process}/maps').decode()
result = {'installedApkSha256': hashlib.sha256(installed).hexdigest(), 'libraries': []}
with zipfile.ZipFile(io.BytesIO(installed)) as archive:
    for name in ['lib/arm64-v8a/libmobi.so', 'lib/arm64-v8a/libbookfin_mobi.so']:
        entry = archive.getinfo(name)
        header = installed[entry.header_offset:entry.header_offset + 30]
        filename_length, extra_length = struct.unpack_from('<HH', header, 26)
        offset = entry.header_offset + 30 + filename_length + extra_length
        data = archive.read(name)
        matching = []
        for line in maps.splitlines():
            fields = line.split()
            if fields[-1] == package and offset <= int(fields[2], 16) < offset + len(data):
                matching.append(line)
        result['libraries'].append({'entry': name, 'sha256': hashlib.sha256(data).hexdigest(), 'apkDataOffset': offset,
                                    'bytes': len(data), 'replacementMarkerInLibrary': b'bookfin-interface-compatible-replacement' in data,
                                    'executableMappingVerified': any('r-xp' in line for line in matching), 'maps': matching})
output = Path(__file__).resolve().parent / 'companion-native-identity.json'
output.write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps({'apkSha256': result['installedApkSha256'],
                  'allExecutableMappingsVerified': all(item['executableMappingVerified'] for item in result['libraries']),
                  'replacementMarkerPresent': result['libraries'][0]['replacementMarkerInLibrary']}))
