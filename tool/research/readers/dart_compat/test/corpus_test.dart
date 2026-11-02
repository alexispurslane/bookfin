import 'dart:convert';
import 'dart:io';

import 'package:epubx/epubx.dart';
import 'package:test/test.dart';

void main() {
  final enabled = Platform.environment['BOOKFIN_REAL_CORPUS'] == '1';
  final manifest = jsonDecode(
    File('../corpus-manifest.json').readAsStringSync(),
  );
  final observations = <String, Object?>{};
  group(
    'Public-source EPUB parser observations',
    () {
      tearDownAll(() {
        if (enabled) {
          File('../_out/corpus/dart-epub-observations.json').writeAsStringSync(
            '${const JsonEncoder.withIndent('  ').convert(observations)}\n',
          );
        }
      });
      for (final sample in manifest['samples']) {
        if (!['epub', 'mobi'].contains(sample['format'])) continue;
        test('${sample['id']} retains opening and later text in spine resources', () async {
          final filename = sample['filename'] as String;
          final path = sample['format'] == 'epub'
              ? '../_out/corpus/originals/$filename'
              : '../_out/corpus/converted/${filename.replaceAll('.mobi', '.epub')}';
          final book = await EpubReader.readBook(File(path).readAsBytesSync());
          final package = book.Schema!.Package!;
          final content = book.Content!;
          final spineFiles = [
            for (final entry in package.Spine!.Items!)
              package.Manifest!.Items!
                  .singleWhere((item) => item.Id == entry.IdRef)
                  .Href!,
          ];
          final text = spineFiles
              .map((path) => content.Html![path]!.Content!)
              .join('\n');
          final phrases = <String, bool>{
            for (final phrase in sample['expected_phrases'])
              phrase as String: text.toLowerCase().contains(
                (phrase as String).toLowerCase(),
              ),
          };
          observations[sample['id']] = {
            'title': book.Title,
            'spine_files': spineFiles,
            'html_resources': content.Html!.length,
            'images': {
              for (final image in content.Images!.entries)
                image.key: {
                  'bytes': image.value.Content!.length,
                  'mime': image.value.ContentMimeType,
                },
            },
            'expected_phrases': phrases,
            'raw_spine_html_characters': text.length,
          };
          expect(spineFiles, isNotEmpty);
          expect(phrases.values, everyElement(isTrue));
          expect(content.Images!.values, isNotEmpty);
          expect(
            content.Images!.values.every((image) => image.Content!.isNotEmpty),
            isTrue,
          );
        });
      }
    },
    skip: enabled
        ? false
        : 'Set BOOKFIN_REAL_CORPUS=1 after acquiring the pinned public corpus',
  );
}
