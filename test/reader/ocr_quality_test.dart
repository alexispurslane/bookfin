import 'package:bookfin/reader/ocr.dart';
import 'package:bookfin/reader/pdf.dart';
import 'package:flutter_test/flutter_test.dart';

String line(String words, int left, int top, int right, int bottom) =>
    '<span class="ocr_line" title="bbox $left $top $right $bottom">${words.split(' ').map((word) => '<span class="ocrx_word">$word</span>').join(' ')}</span>';

void main() {
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
    expect(result.reason, contains('original page'));
  });

  test('parallel recognized lines retain the original instead of combining columns', () {
    final result = decodeRecognizedPage(
      '<div>${List.generate(3, (index) => '${line('Left column words', 10, index * 40, 200, index * 40 + 20)}${line('Right column words', 400, index * 40, 600, index * 40 + 20)}').join()}</div>',
    );
    expect(result.status, PdfTextStatus.unreliable);
  });

  test(
    'recognition with no words keeps an explicit original-page fallback',
    () {
      final result = decodeRecognizedPage('<div class="ocr_page"/>');
      expect(result.status, PdfTextStatus.absent);
      expect(result.reason, contains('No English text'));
    },
  );

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
