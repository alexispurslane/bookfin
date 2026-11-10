// Behavior tests of Tesseract's layout pass on Android, through the
// recognition channel that Bookfin uses. Run them on your own emulator with
// tool/reader/ocr_layout_device_test.py, which serves the test pages.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bookfin/downloads/downloads.dart';
import 'package:bookfin/reader/ocr.dart';
import 'package:bookfin/reader/pdf.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _pages = String.fromEnvironment('BOOKFIN_LAYOUT_PAGES');
const _record = bool.fromEnvironment('BOOKFIN_LAYOUT_RECORD');
const _channel = MethodChannel('bookfin/ocr');

/// One entry of a layout record: nine numbers, in Tesseract's order.
typedef _Entry = ({
  int kind,
  int left,
  int top,
  int right,
  int bottom,
  int a,
  int b,
  int c,
  int d,
});

const _page = 0, _block = 1, _paragraph = 2, _line = 3, _word = 4;

/// Tesseract's picture block types: flowing, heading and pullout images.
const _pictures = {9, 10, 11};

/// The SHA-256 of the hOCR that Bookfin's Java TessBaseAPI engine gave for
/// each page on the emulator before the move to the C API (commit 8bc40c5),
/// for a page that PDFium drew 1600 pixels wide.
const _javaEngineHocr = <String, String>{
  'scanned.pdf#1':
      '4d8ad2eaa2224311bedc7261eb9930ebd8b31ee816cd1305d50d4adeaf837c9d',
  'skewed.pdf#1':
      '9417203aa4398f3f761605c516edd5d04e448ea7a2ad81348e7be14efdc1f1a1',
  'nist-cloud.pdf#3':
      '1b018b846ddc78f3382e2469e6541f5b7f903900f4e126b14b4fb837ed6e84c5',
  'nist-cloud.pdf#6':
      '8a379460d122933ad0b455c986853f7ab6cfcab87690a0805596b48d9ed2f0df',
  'census-notice.pdf#1':
      '584d5961119b27ab1a1123221b57a53c8e6db3379225633265782198ce0fd626',
  'census-notice.pdf#2':
      '7494981b3bad9b9234c26fd5392680dd1e77192ff59c5696cad166ea9cacd636',
  'raven-1873.pdf#12':
      '9d9648456b3c0c88fe4d83a6e5c898d9ae1abe479b5b5750b5d58d09ebe3da5b',
  'raven-1873.pdf#13':
      '84e587e1882a2356f6a620511f2cf03808eba45d15578bc63bab59cef755e72c',
};

final _rasters = <String, PdfRaster>{};

Future<PdfRaster> _raster(String file, int page) async {
  final name = '$file#$page';
  final cached = _rasters[name];
  if (cached != null) return cached;
  final client = HttpClient();
  final Uint8List bytes;
  try {
    final response = await (await client.getUrl(Uri.parse('$_pages/$file')))
        .close();
    if (response.statusCode != 200) throw StateError('No test page $file.');
    final builder = BytesBuilder(copy: false);
    await response.forEach(builder.add);
    bytes = builder.takeBytes();
  } finally {
    client.close();
  }
  final book = await PdfRuntime.instance.open(
    bytes,
    sha256.convert(bytes).toString(),
  );
  try {
    return _rasters[name] = await book.render(page, 1600);
  } finally {
    await book.dispose();
  }
}

/// The served file [name], or null when the runner serves none.
Future<String?> _served(String name) async {
  final client = HttpClient();
  try {
    final response = await (await client.getUrl(Uri.parse('$_pages/$name')))
        .close();
    if (response.statusCode != 200) {
      await response.drain<void>();
      return null;
    }
    return await response.transform(utf8.decoder).join();
  } finally {
    client.close();
  }
}

/// Sends [text] to the runner, which keeps it as the fixture [name].
Future<void> _send(String name, String text) async {
  final client = HttpClient();
  try {
    final request = await client.putUrl(Uri.parse('$_pages/$name'));
    final bytes = utf8.encode(text);
    request.contentLength = bytes.length;
    request.add(bytes);
    final response = await request.close();
    await response.drain<void>();
    expect(response.statusCode, 204);
  } finally {
    client.close();
  }
}

/// A layout record as the fixtures keep it: one entry a line, its nine
/// numbers separated by spaces.
String _layoutText(Int32List record) => [
  for (var index = 0; index < record.length; index += 9)
    '${record.sublist(index, index + 9).join(' ')}\n',
].join();

Map<String, Object> _image(PdfRaster raster) => {
  'width': raster.width,
  'height': raster.height,
  'bgra': raster.bgra,
};

Future<List<_Entry>> _layout(PdfRaster raster) async {
  final record = (await _channel.invokeMethod<Int32List>(
    'layout',
    _image(raster),
  ))!;
  expect(record.length % 9, 0, reason: 'Each entry has nine numbers.');
  return [
    for (var index = 0; index < record.length; index += 9)
      (
        kind: record[index],
        left: record[index + 1],
        top: record[index + 2],
        right: record[index + 3],
        bottom: record[index + 4],
        a: record[index + 5],
        b: record[index + 6],
        c: record[index + 7],
        d: record[index + 8],
      ),
  ];
}

Future<String> _recognize(PdfRaster raster) async =>
    await _channel.invokeMethod<String>('recognize', _image(raster)) ?? '';

/// Recognizes the image that the last layout pass kept.
Future<String> _recognizeKept() async =>
    await _channel.invokeMethod<String>('recognize') ?? '';

/// The boxes of the recognized words of [hocr], in hOCR order.
List<List<int>> _hocrWords(String hocr) => [
  for (final match in RegExp(
    r"class='ocrx_word'[^>]*title='bbox (\d+) (\d+) (\d+) (\d+)",
  ).allMatches(hocr))
    [for (var group = 1; group <= 4; group++) int.parse(match.group(group)!)],
];

int _overlap(_Entry word, List<int> box) {
  final width =
      math.min<int>(word.right, box[2]) - math.max<int>(word.left, box[0]);
  final height =
      math.min<int>(word.bottom, box[3]) - math.max<int>(word.top, box[1]);
  return width > 0 && height > 0 ? width * height : 0;
}

bool _holds(_Entry outer, _Entry inner, int slack) =>
    inner.left >= outer.left - slack &&
    inner.top >= outer.top - slack &&
    inner.right <= outer.right + slack &&
    inner.bottom <= outer.bottom + slack;

/// The pages whose hOCR must not change: the scanned and skewed test pages,
/// and dense pages of the pinned corpus.
const _identityPages = [
  ('scanned.pdf', 1),
  ('skewed.pdf', 1),
  ('nist-cloud.pdf', 3),
  ('nist-cloud.pdf', 6),
  ('census-notice.pdf', 1),
  ('census-notice.pdf', 2),
  ('raven-1873.pdf', 12),
  ('raven-1873.pdf', 13),
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the layout pass gives the scanned page its blocks, '
      'paragraphs, lines and words in reading order, in raster pixels', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final raster = await _raster('scanned.pdf', 1);
      final entries = await _layout(raster);
      final hocr = await _recognizeKept();

      expect(entries.first, (
        kind: _page,
        left: 0,
        top: 0,
        right: raster.width,
        bottom: raster.height,
        a: 0,
        b: 0,
        c: 0,
        d: 0,
      ));
      _Entry? block, paragraph, line;
      final words = <_Entry>[];
      for (final (index, entry) in entries.indexed.skip(1)) {
        final previous = entries[index - 1].kind;
        expect(entry.left, inInclusiveRange(0, raster.width));
        expect(entry.right, inInclusiveRange(entry.left + 1, raster.width));
        expect(entry.top, inInclusiveRange(0, raster.height));
        expect(entry.bottom, inInclusiveRange(entry.top + 1, raster.height));
        switch (entry.kind) {
          case _block:
            block = entry;
            paragraph = line = null;
          case _paragraph:
            expect(previous, anyOf(_block, _word));
            expect(_holds(block!, entry, 2), isTrue);
            paragraph = entry;
          case _line:
            expect(previous, anyOf(_paragraph, _word));
            expect(_holds(paragraph!, entry, 2), isTrue);
            line = entry;
          case _word:
            expect(previous, anyOf(_line, _word));
            expect(_holds(line!, entry, 2), isTrue);
            words.add(entry);
          default:
            fail('Unknown entry kind ${entry.kind}.');
        }
      }
      expect(words.length, greaterThan(20));
      final recognized = _hocrWords(hocr);
      final order = [
        for (final word in words)
          if (recognized.any((box) => _overlap(word, box) > 0))
            recognized.indexed
                .reduce(
                  (best, next) =>
                      _overlap(word, next.$2) > _overlap(word, best.$2)
                      ? next
                      : best,
                )
                .$1,
      ];
      expect(order.length, greaterThan(words.length * 3 ~/ 4));
      for (var index = 1; index < order.length; index++) {
        expect(order[index], greaterThanOrEqualTo(order[index - 1]));
      }
    });
  });

  testWidgets('the engraving of the scanned page is a picture block', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final raster = await _raster('scanned.pdf', 1);
      final entries = await _layout(raster);
      await _recognizeKept();
      final pictures = [
        for (final (index, entry) in entries.indexed)
          if (entry.kind == _block &&
              _pictures.contains(entry.a) &&
              (entry.right - entry.left) * (entry.bottom - entry.top) >
                  raster.width * raster.height / 4)
            index,
      ];
      expect(pictures, isNotEmpty);
      // As in hOCR, a picture is one box, without lines or words.
      for (final index in pictures) {
        if (index + 1 < entries.length) {
          expect(entries[index + 1].kind, _block);
        }
      }
    });
  });

  testWidgets('the lines of the skewed page slope by 2.5 degrees', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final raster = await _raster('skewed.pdf', 1);
      final entries = await _layout(raster);
      await _recognizeKept();
      // A baseline's ends are whole pixels, so only a line wider than a
      // quarter of the page, 400 pixels, measures its slope to 0.15
      // degrees.
      final slopes = [
        for (final line in entries)
          if (line.kind == _line && line.c - line.a > raster.width / 4)
            math.atan2(line.d - line.b, line.c - line.a) * 180 / math.pi,
      ];
      debugPrint('skewed line slopes in degrees: $slopes');
      expect(slopes.length, greaterThanOrEqualTo(3));
      for (final slope in slopes) {
        expect(slope.abs(), closeTo(2.5, 0.2));
      }
    });
  });

  testWidgets('recognition after the layout pass gives the same hOCR, byte '
      'for byte, as recognition alone, and as the Java engine gave', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final times = <String>[];
      final digests = <String, String>{};
      for (final (file, page) in _identityPages) {
        final name = '$file#$page';
        final raster = await _raster(file, page);
        final watch = Stopwatch()..start();
        final alone = await _recognize(raster);
        final recognition = watch.elapsedMilliseconds;
        watch.reset();
        final entries = await _layout(raster);
        final layout = watch.elapsedMilliseconds;
        watch.reset();
        final after = await _recognizeKept();
        final afterLayout = watch.elapsedMilliseconds;
        final digest = sha256.convert(utf8.encode(alone)).toString();
        digests[name] = digest;
        times.add(
          '$name ${raster.width}x${raster.height}: layout $layout ms, '
          'recognition after layout $afterLayout ms, recognition alone '
          '$recognition ms, ${entries.where((e) => e.kind == _word).length} '
          'layout words, ${_hocrWords(alone).length} hOCR words',
        );
        expect(after, alone, reason: name);
      }
      debugPrint(times.join('\n'));
      debugPrint('hOCR digests: ${jsonEncode(digests)}');
      expect(digests, _javaEngineHocr);
    });
  });

  testWidgets('recognition of a kept image needs a layout pass first, and '
      'its refusal leaves recognition working', (tester) async {
    await tester.runAsync(() async {
      final raster = await _raster('scanned.pdf', 1);
      final alone = await _recognize(raster);
      await expectLater(
        _recognizeKept(),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'recognition',
          ),
        ),
      );
      expect(await _recognize(raster), alone);
    });
  });

  testWidgets('a later layout pass replaces the kept image', (tester) async {
    await tester.runAsync(() async {
      final scanned = await _raster('scanned.pdf', 1);
      final skewed = await _raster('skewed.pdf', 1);
      final alone = await _recognize(skewed);
      await _layout(scanned);
      await _layout(skewed);
      expect(await _recognizeKept(), alone);
    });
  });

  testWidgets('the reflow fixtures hold the layout records and the hOCR '
      'that the emulator gives for the scanned, skewed and footnote pages', (
    tester,
  ) async {
    await tester.runAsync(() async {
      for (final (file, fixture) in [
        ('scanned.pdf', 'scanned-page'),
        ('skewed.pdf', 'skewed-page'),
        ('footnote.pdf', 'footnote-page'),
      ]) {
        final raster = await _raster(file, 1);
        final record = (await _channel.invokeMethod<Int32List>(
          'layout',
          _image(raster),
        ))!;
        final hocr = await _recognizeKept();
        final layout = _layoutText(record);
        if (_record) {
          await _send('$fixture.layout', layout);
          await _send('$fixture.hocr', hocr);
        } else {
          expect(layout, await _served('$fixture.layout'), reason: fixture);
          expect(hocr, await _served('$fixture.hocr'), reason: fixture);
        }
      }
    });
  });

  testWidgets('a scanned page gets its words from the layout pass, then '
      'its text from the kept image, with the digest of recognition alone, '
      'attached to those words', (tester) async {
    await tester.runAsync(() async {
      final folder = await Directory.systemTemp.createTemp('bookfin-words-');
      try {
        for (final (name, digest) in [
          (
            'scanned.pdf',
            'b445f1857d95e243154bfeb056e7df3b477586153e917f78f3477f0a319d25b4',
          ),
          (
            'skewed.pdf',
            '123831d0d61cde195f9a31b52fe745beb49311c930a79857dc7f0aa8e4b4e736',
          ),
        ]) {
          final client = HttpClient();
          final Uint8List bytes;
          try {
            final response = await (await client.getUrl(
              Uri.parse('$_pages/$name'),
            )).close();
            final builder = BytesBuilder(copy: false);
            await response.forEach(builder.add);
            bytes = builder.takeBytes();
          } finally {
            client.close();
          }
          final file = await File('${folder.path}/$name').writeAsBytes(bytes);
          final original = VerifiedFile(
            file.uri,
            sha256.convert(bytes).toString(),
          );
          final supply = BundledEnglishText();
          final book = await PdfRuntime.instance.open(
            bytes,
            original.digest,
            textSupply: supply,
          );
          supply.bind((read) => read(original, () => true));
          try {
            final watch = Stopwatch()..start();
            final words = book.geometry(1);
            final attached = words.then(
              (geometry) => book.attachedText(1, geometry!),
            );
            final geometry = (await words)!;
            final wordsAt = watch.elapsedMilliseconds;
            final text = await attached;
            final textAt = watch.elapsedMilliseconds;
            debugPrint(
              '$name: ${geometry.wordCount} words after $wordsAt ms, '
              'text attached after $textAt ms',
            );
            expect(geometry.wordCount, greaterThan(30));
            expect(text.text.digest, digest, reason: name);
            geometry.checkInvariants(
              attachment: text.attachment,
              source: text.text.source,
            );
            final named = [
              for (var word = 0; word < geometry.wordCount; word++)
                if (text.attachment![word * 2] < text.attachment![word * 2 + 1])
                  word,
            ];
            expect(named.length, greaterThan(geometry.wordCount * 9 ~/ 10));
            EnglishRecognition.instance.checkInvariants();
          } finally {
            await book.dispose();
          }
        }
      } finally {
        await folder.delete(recursive: true);
      }
    });
  });
}
