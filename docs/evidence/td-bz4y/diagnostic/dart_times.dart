import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import 'compat_test.dart' as fixtures;

final times = [DateTime(2026, 1, 1, 12), DateTime(2026, 1, 1, 12, 0, 2)];

List<int> build(DateTime clock, {bool changed = false}) {
  final bytes = runZoned(
    fixtures.diagnosticCoverArchive,
    zoneValues: {#tdBz4yArchiveTime: clock},
  );
  print('OBSERVATION ${jsonEncode({
    'clock': clock.toIso8601String(),
    'changed': changed,
    'sha256': sha256.convert(bytes).toString(),
    'entries': [
      for (final entry in ZipDecoder().decodeBytes(bytes))
        {
          'name': entry.name,
          'time': entry.lastModTime,
          'payloadSha256': sha256.convert(entry.content).toString(),
          'compression': entry.compression?.name,
          'mode': entry.mode,
        },
    ],
  })}');
  return bytes;
}

void main() {
  test('clock control changes unfixed archive bytes', () {
    List<int> control(DateTime time) => runZoned(
      () => ZipEncoder().encode(
        Archive()..addFile(ArchiveFile.string('control.txt', 'unchanged')),
      ),
      zoneValues: {#tdBz4yArchiveTime: time},
    );
    expect(control(times[0]), isNot(orderedEquals(control(times[1]))));
  });

  test('cover replacement bytes do not depend on encoding time', () {
    final first = build(times[0]);
    final second = build(times[1]);
    expect(second, orderedEquals(first));
  });

  test('changed source content still changes cover replacement bytes', () {
    final first = build(times[0]);
    final source = File('../_out/mobi6-plain.epub');
    final originalBytes = source.readAsBytesSync();
    try {
      final archive = ZipDecoder().decodeBytes(originalBytes);
      final original = archive.findFile('OEBPS/content.opf')!;
      final metadata = utf8.decode(original.content);
      final changed = metadata.replaceFirst('<dc:title>', '<dc:title>Changed ');
      expect(changed, isNot(metadata));
      archive.addFile(
        ArchiveFile.string(original.name, changed)
          ..lastModTime = original.lastModTime,
      );
      source.writeAsBytesSync(ZipEncoder().encode(archive));
      expect(build(times[0], changed: true), isNot(orderedEquals(first)));
    } finally {
      source.writeAsBytesSync(originalBytes);
    }
  });
}
