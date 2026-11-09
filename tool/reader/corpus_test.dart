import 'dart:convert';
import 'dart:io';

import 'package:bookfin/reader/epub/publication.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final samples = jsonDecode(
    File('.cache/navigator/books.json').readAsStringSync(),
  ) as List;
  final exported = <Map<String, dynamic>>[];
  for (final sample in samples) {
    test(
      '${sample['id']}: real admission retains a navigable passive publication',
      () async {
        final bytes = await File(sample['epub'] as String).readAsBytes();
        expect(sha256.convert(bytes).toString(), sample['epub_sha256']);
        final publication = Publication.admit(bytes);
        publication.checkInvariants();
        final root = Directory('.cache/reader-corpus/${sample['id']}');
        for (final entry in publication.resources.entries) {
          final file = File('${root.path}/${entry.key}');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(entry.value);
        }
        expect(publication.spine, isNotEmpty);
        exported.add({
          'id': sample['id'],
          'directory': root.absolute.path,
          'phrase': sample['phrase'],
          'base': publication.base.toString(),
          'packagePath': publication.packagePath,
          'original': publication.originalDigest,
          'processed': publication.identity,
          'spine': publication.spine.length,
          'resources': publication.resources.length,
          'warnings': publication.warnings,
        });
      },
    );
  }
  tearDownAll(() async {
    expect(exported, hasLength(9));
    await File('.cache/reader-corpus/books.json')
        .writeAsString(const JsonEncoder.withIndent('  ').convert(exported));
  });
}
