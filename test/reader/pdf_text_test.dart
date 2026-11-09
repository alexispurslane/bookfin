import 'dart:isolate';
import 'dart:typed_data';

import 'package:bookfin/reader/pdf.dart';
import 'package:flutter_test/flutter_test.dart';

/// Character boxes that set [source] on one line, one box for each UTF-16
/// code unit, as left, top, right and bottom in PDF points.
Float64List oneLine(String source) {
  final boxes = Float64List(source.length * 4);
  for (var index = 0; index < source.length; index++) {
    boxes.setAll(index * 4, [index * 6.0, 20, index * 6.0 + 5, 10]);
  }
  return boxes;
}

PdfText prepared(String source) =>
    preparePdfPage((source: source, boxes: oneLine(source)));

void main() {
  test('a page text joins each run of whitespace into one space and maps every '
      'reflowed character to its source character', () {
    final text = prepared('  The river\r\n\tfollows   the  road.  ');
    expect(text.text, 'The river follows the road.');
    expect(text.sourceOffsets, [
      2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 14, 15, 16, 17, 18, 19, 20, 21, //
      24, 25, 26, 27, 29, 30, 31, 32, 33,
    ]);
    expect(text.status, PdfTextStatus.candidate);
    expect(text.source, '  The river\r\n\tfollows   the  road.  ');
  });

  test('exactly the characters that a regular expression calls whitespace '
      'separate words in a page text', () {
    // Saved places count reflowed characters, so the whitespace set must
    // stay the one that page text used when they were saved.
    final whitespace = RegExp(r'\s');
    final wrong = <String>[];
    for (var unit = 0; unit <= 0xFFFF; unit++) {
      final character = String.fromCharCode(unit);
      final text = prepared('a${character}b');
      final joined = whitespace.hasMatch(character);
      if (text.text != (joined ? 'a b' : 'a${character}b') ||
          text.sourceOffsets.join(',') != '0,1,2') {
        wrong.add(unit.toRadixString(16));
      }
    }
    expect(wrong, isEmpty);
  });

  test(
    'a candidate page text names its text by the SHA-256 of its UTF-8 bytes',
    () {
      // Saved places name their page text this way, so a change here
      // would make every saved place inside a page fall back to the page.
      expect(
        prepared('Café river').digest,
        '93b6d5f73c8945916da6026905effd61191387b87183a768121c5f92d231b4cf',
      );
      expect(pdfTextDigest('Café river'), prepared('Café river').digest);
    },
  );

  test('a page without extracted text offers the original page', () {
    final text = prepared(' \n ');
    expect(text.status, PdfTextStatus.absent);
    expect(text.reason, 'This page has no text to reflow.');
    expect(text.digest, isNull);
  });

  test(
    'a page whose characters do not each have a box offers the original page',
    () {
      final text = preparePdfPage((source: 'river', boxes: oneLine('rive')));
      expect(text.text, 'river');
      expect(text.status, PdfTextStatus.unreliable);
      expect(text.reason, contains('reading order'));
    },
  );

  test(
    'a page with a character box outside the page offers the original page',
    () {
      final boxes = oneLine('river')..[2 * 4 + 1] = double.infinity;
      final text = preparePdfPage((source: 'river', boxes: boxes));
      expect(text.status, PdfTextStatus.unreliable);
      expect(text.reason, contains('reading order'));
    },
  );

  test(
    'a page text at the size limit is prepared whole in a worker isolate',
    () async {
      final source = List.filled(400000, 'word ').join();
      final page = (source: source, boxes: oneLine(source));
      final text = await Isolate.run(() => preparePdfPage(page));
      expect(text.text.length, source.length - 1);
      expect(text.sourceOffsets, hasLength(source.length - 1));
      expect(text.digest, pdfTextDigest(source));
    },
  );
}
