import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bookfin/reader/epub/publication.dart';
import 'package:bookfin/reader/mobi.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the Alice layout fixture retains the recorded Android edition', () async {
    final output = Platform.environment['BOOKFIN_KF8_LAYOUT_DIRECTORY'];
    if (output == null) {
      throw StateError('Run this fixture through engine/test/layout.test.cjs.');
    }
    final original = await File('tool/research/readers/fixtures/pg11-kf8.mobi')
        .copy('$output/original.mobi');
    final digest = sha256.convert(await original.readAsBytes()).toString();
    final document = await importMobi(original, digest);
    addTearDown(document.dispose);
    expect(
      document.originalDigest,
      'd8211269aed55ded8302f289950936db8368b4d4d384c463b722034152f8f1d2',
    );
    expect(
      document.identity,
      '3d0b0318cf5d0455722a2b8ccf93ac5ec0be08e0c198a831d41d4990be1f10d7',
    );
    final converted = await File(
      '$output/.bookfin-mobi/${document.originalDigest}-libmobi-0.12-v1/book.epub',
    ).readAsBytes();
    final headers = ByteData.sublistView(converted);
    expect(headers.getUint32(converted.length - 22, Endian.little), 0x06054b50);
    var central = headers.getUint32(converted.length - 6, Endian.little);
    final androidTime = (9 << 11) | (56 << 5) | (26 ~/ 2);
    final androidDate = ((2026 - 1980) << 9) | (11 << 5) | 3;
    while (headers.getUint32(central, Endian.little) == 0x02014b50) {
      final local = headers.getUint32(central + 42, Endian.little);
      expect(headers.getUint32(local, Endian.little), 0x04034b50);
      for (final offset in [local + 10, central + 12]) {
        headers.setUint16(offset, androidTime, Endian.little);
        headers.setUint16(offset + 2, androidDate, Endian.little);
      }
      central +=
          46 +
          headers.getUint16(central + 28, Endian.little) +
          headers.getUint16(central + 30, Endian.little) +
          headers.getUint16(central + 32, Endian.little);
    }
    expect(
      sha256.convert(converted).toString(),
      '2f6de175d5f69498afb7d8e941dfed0253e11881cfd1628556f959db71ec8fa8',
    );
    final publication = Publication.admit(converted);
    // Every admitted file, the images and fonts too.
    Future<Map<String, Uint8List>> files(Publication publication) async => {
      for (final path in publication.mediaTypes.keys)
        path: (await publication.bytesOf(path))!,
    };
    final admitted = await files(publication);
    expect(admitted, await files(document.publication));
    final cached = await importMobi(original, digest);
    addTearDown(cached.dispose);
    expect(cached.identity, document.identity);
    expect(await files(cached.publication), admitted);
    for (final MapEntry(key: path, value: bytes) in admitted.entries) {
      final file = File('$output/publication/$path');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);
    }
    await File('$output/publication.json').writeAsString(
      jsonEncode({
        'packagePath': publication.packagePath,
        'original': document.originalDigest,
        'processed': document.identity,
        'converted': publication.originalDigest,
      }),
    );
  });
}
