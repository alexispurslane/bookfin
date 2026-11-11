// An on-demand host benchmark of a PDF's open (boo-yjq6): the open of the
// file through the PDF runtime, and the open with the first render of a
// later page at 1080 pixels.
//
// In the dev shell, from the repository root:
//
//   BOOKFIN_PDF_OPEN_BENCHMARK=<path>[,<path>] flutter test \
//     test/reader/pdf_open_benchmark_test.dart
//
// It prints a PDF_OPEN_BENCHMARK line for each file, with medians of
// BOOKFIN_PDF_OPEN_ROUNDS rounds (5).
import 'dart:io';

import 'package:bookfin/reader/pdf.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart' as native;

void main() {
  final paths = Platform.environment['BOOKFIN_PDF_OPEN_BENCHMARK'];
  if (paths == null) {
    test(
      'the open of a PDF',
      () {},
      skip: 'set BOOKFIN_PDF_OPEN_BENCHMARK to the paths of PDF files',
    );
    return;
  }
  final rounds = int.parse(
    Platform.environment['BOOKFIN_PDF_OPEN_ROUNDS'] ?? '5',
  );
  TestWidgetsFlutterBinding.ensureInitialized();
  native.Pdfrx.pdfiumModulePath = Platform.environment['PDFIUM_LIBRARY'];
  native.Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;
  double median(List<int> microseconds) =>
      (microseconds..sort())[microseconds.length ~/ 2] / 1000;
  for (final path in paths.split(',')) {
    test(path, () async {
      final opens = <int>[], renders = <int>[];
      var pages = 0, page = 0;
      for (var round = 0; round <= rounds; round++) {
        final watch = Stopwatch()..start();
        final book = await PdfRuntime.instance.open(
          path,
          '$round'.padLeft(64, '0'),
        );
        final opened = watch.elapsedMicroseconds;
        pages = book.pageCount;
        page = 100.clamp(1, pages);
        await book.render(page, 1080);
        final rendered = watch.elapsedMicroseconds;
        await book.dispose();
        // The first round warms the engine up.
        if (round == 0) continue;
        opens.add(opened);
        renders.add(rendered);
      }
      // ignore: avoid_print
      print(
        'PDF_OPEN_BENCHMARK ${path.split('/').last} pages=$pages '
        'open=${median(opens)} open+render(page $page)=${median(renders)} ms '
        '(median of $rounds)',
      );
    }, timeout: Timeout.none);
  }
}
