import argparse
import ctypes
import json
import os
from pathlib import Path
import shutil
import subprocess
from zipfile import ZipFile

from native_package import ROOT, digest, verify


def run(*command):
    subprocess.run([str(part) for part in command], check=True, cwd=ROOT)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('apk', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--keystore', type=Path, default=Path.home() / '.android/debug.keystore')
    args = parser.parse_args()
    apk = args.apk.resolve()
    output = args.output.resolve()
    if not args.keystore.is_file():
        raise ValueError('Pass an existing disposable debug keystore. No global key is created.')
    verify(apk)
    output.mkdir(parents=True, exist_ok=False)
    source = output / 'libmobi'
    shutil.copytree(os.environ['BOOKFIN_LIBMOBI_SOURCE'], source)
    util = source / 'src/util.c'
    util.chmod(0o644)
    original = util.read_text()
    marker = 'bookfin-interface-compatible-replacement'
    modified = original.replace('return PACKAGE_VERSION;', 'return "' + marker + '";')
    if original == modified:
        raise ValueError('The pinned libmobi version function was not found.')
    util.write_text(modified)
    bridge = ROOT / 'native/mobi'
    host = output / 'host'
    run('cmake', '-S', bridge, '-B', host, '-DBOOKFIN_LIBMOBI_SOURCE=' + str(source))
    run('cmake', '--build', host, '--target', 'bookfin_mobi', '--parallel', '2')
    library = ctypes.CDLL(str(host / 'libmobi/src/libmobi.dylib'))
    library.mobi_version.restype = ctypes.c_char_p
    if library.mobi_version().decode() != marker:
        raise ValueError('Host loading did not use the modified library.')
    converter = ctypes.CDLL(str(host / 'libbookfin_mobi.dylib'))
    converter.bookfin_convert.argtypes = [ctypes.c_char_p]
    converter.bookfin_convert.restype = ctypes.c_int
    sample = output / 'replacement.mobi'
    shutil.copyfile(ROOT / 'tool/research/readers/fixtures/pg11-kf8.mobi', sample)
    if converter.bookfin_convert(os.fsencode(sample)) != 0:
        raise ValueError('The modified host library could not convert the pinned KF8 sample.')
    with ZipFile(sample.with_suffix('.epub')) as publication:
        if publication.testzip() is not None or not publication.read('META-INF/container.xml'):
            raise ValueError('Modified-library conversion did not produce an EPUB container.')
    android = output / 'android'
    sdk = Path(os.environ['ANDROID_HOME'])
    toolchain = sdk / 'ndk/28.2.13676358/build/cmake/android.toolchain.cmake'
    run('cmake', '-G', 'Ninja', '-S', bridge, '-B', android,
        '-DCMAKE_TOOLCHAIN_FILE=' + str(toolchain), '-DANDROID_ABI=arm64-v8a',
        '-DANDROID_PLATFORM=android-24', '-DBOOKFIN_LIBMOBI_SOURCE=' + str(source))
    run('cmake', '--build', android, '--target', 'bookfin_mobi', '--parallel', '2')
    replacement = android / 'libmobi/src/libmobi.so'
    unsigned = output / 'unsigned.apk'
    replaced = 'lib/arm64-v8a/libmobi.so'
    with ZipFile(apk) as original_apk, ZipFile(unsigned, 'w') as rewritten:
        signatures = {name for name in original_apk.namelist() if name.startswith('META-INF/') and (name.endswith(('.SF', '.RSA', '.DSA', '.EC')) or name == 'META-INF/MANIFEST.MF')}
        for entry in original_apk.infolist():
            if entry.filename in signatures:
                continue
            rewritten.writestr(entry, replacement.read_bytes() if entry.filename == replaced else original_apk.read(entry))
    build_tools = sdk / 'build-tools/36.0.0'
    aligned = output / 'aligned.apk'
    run(build_tools / 'zipalign', '-P', '16', '4', unsigned, aligned)
    candidate = output / 'bookfin-replacement.apk'
    run(build_tools / 'apksigner', 'sign', '--ks', args.keystore, '--ks-pass', 'pass:android',
        '--key-pass', 'pass:android', '--out', candidate, aligned)
    run(build_tools / 'apksigner', 'verify', '--verbose', candidate)
    run(build_tools / 'zipalign', '-c', '-P', '16', '4', candidate)
    verify(candidate)
    with ZipFile(apk) as original_apk, ZipFile(candidate) as changed_apk:
        changed = [name for name in original_apk.namelist() if name not in signatures and original_apk.read(name) != changed_apk.read(name)]
    if changed != [replaced]:
        raise ValueError('The replacement changed unexpected application entries: ' + repr(changed))
    result = {'originalApk': digest(apk), 'replacementApk': digest(candidate),
        'modifiedLibrary': digest(replacement), 'changedEntries': changed,
        'hostVersion': marker, 'hostKf8Conversion': 'passed', 'androidInstalled': False}
    (output / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
