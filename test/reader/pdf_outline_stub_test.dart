import 'package:bookfin/reader/pdf_outline_stub.dart' as browser;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the browser cannot measure a PDF file as an empty outline', () async {
    await expectLater(
      browser.measurePdfOutline('book.pdf'),
      throwsUnsupportedError,
    );
  });
}
