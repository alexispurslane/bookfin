import 'package:bookfin/reader/ocr.dart';
import 'package:bookfin/reader/pdf.dart';
import 'package:flutter_test/flutter_test.dart';

String line(String words, int left, int top, int right, int bottom) =>
    '<span class="ocr_line" title="bbox $left $top $right $bottom">${words.split(' ').map((word) => '<span class="ocrx_word">$word</span>').join(' ')}</span>';

void main() {
  test('nested words cannot publish the same recognized characters twice', () {
    expect(
      () => decodeRecognizedPage(
        '<span class="ocr_line" title="bbox 10 10 300 30"><span class="ocrx_word">Outer<span class="ocrx_word">inner</span></span></span>',
      ),
      throwsFormatException,
    );
  });
  test('all pinned textual line classes keep their words in source order', () {
    final result = decodeRecognizedPage(
      '<div>${line('A chapter heading', 10, 10, 300, 30).replaceAll('ocr_line', 'ocr_header')}${line('The body follows', 10, 45, 300, 65)}${line('A floating note', 10, 80, 300, 100).replaceAll('ocr_line', 'ocr_textfloat')}${line('The picture caption', 10, 115, 300, 135).replaceAll('ocr_line', 'ocr_caption')}</div>',
    );
    expect(
      result.source,
      'A chapter heading\nThe body follows\nA floating note\nThe picture caption',
    );
    expect(result.status, PdfTextStatus.candidate);
  });

  test('a heading-only recognized page is not reported as absent', () {
    final result = decodeRecognizedPage(
      '<div>${line('A chapter heading', 10, 10, 300, 30).replaceAll('ocr_line', 'ocr_header')}</div>',
    );
    expect(result.text, 'A chapter heading');
    expect(result.status, PdfTextStatus.candidate);
  });

  test('alternate textual line classes retain conservative column fallback', () {
    final result = decodeRecognizedPage(
      '<div>${List.generate(3, (index) => '${line('Left column words', 10, index * 40, 200, index * 40 + 20).replaceAll('ocr_line', 'ocr_textfloat')}${line('Right column words', 400, index * 40, 600, index * 40 + 20).replaceAll('ocr_line', 'ocr_caption')}').join()}</div>',
    );
    expect(result.status, PdfTextStatus.unreliable);
  });

  test('nested textual lines cannot publish duplicated recognized words', () {
    expect(
      () => decodeRecognizedPage(
        '<div><span class="ocr_header" title="bbox 10 10 300 30">${line('Nested heading words', 10, 10, 300, 30)}</span></div>',
      ),
      throwsFormatException,
    );
  });

  test('recognition preserves page text offsets while flattening line breaks for reflow', () {
    final result = decodeRecognizedPage(
      '<div>${line('One quiet garden', 10, 10, 300, 30)}${line('Three birds arrive.', 10, 45, 300, 65)}</div>',
    );
    expect(result.source, 'One quiet garden\nThree birds arrive.');
    expect(result.text, 'One quiet garden Three birds arrive.');
    expect(
      result.source[result.sourceOffsets[result.text.indexOf('Three')]],
      'T',
    );
  });

  test('short fragments retain the original instead of claiming readable recognition', () {
    final result = decodeRecognizedPage(
      '<div>${List.generate(4, (index) => line('fragment', 10, index * 40, 200, index * 40 + 20)).join()}</div>',
    );
    expect(result.status, PdfTextStatus.unreliable);
  });

  test('parallel recognized lines retain the original instead of combining columns', () {
    final result = decodeRecognizedPage(
      '<div>${List.generate(3, (index) => '${line('Left column words', 10, index * 40, 200, index * 40 + 20)}${line('Right column words', 400, index * 40, 600, index * 40 + 20)}').join()}</div>',
    );
    expect(result.status, PdfTextStatus.unreliable);
  });

  test('recognition with no words offers the original page', () {
    final result = decodeRecognizedPage('<div class="ocr_page"/>');
    expect(result.status, PdfTextStatus.absent);
  });

  test(
    'malformed line geometry cannot become a successful reflow candidate',
    () {
      expect(
        () => decodeRecognizedPage(
          '<div><span class="ocr_line"><span class="ocrx_word">Text</span></span></div>',
        ),
        throwsFormatException,
      );
    },
  );
}
