import 'dart:convert';
import 'dart:io';

import 'package:bookfin/reader/pdf.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Pdfrx.pdfiumModulePath = Platform.environment['PDFIUM_LIBRARY'];
  Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;
  final samples =
      (jsonDecode(
                File('tool/research/readers/corpus-manifest.json')
                    .readAsStringSync(),
              )['samples']
              as List)
          .cast<Map<String, dynamic>>();
  for (final entry in [
    ('nist-cloud.pdf', 5, PdfTextStatus.candidate),
    ('census-notice.pdf', 1, PdfTextStatus.unreliable),
    ('raven-1873.pdf', 9, PdfTextStatus.unreliable),
  ]) {
    test(
      '${entry.$1} source page ${entry.$2} retains the reviewed text-quality boundary',
      () async {
        final bytes = await File('.cache/reader-corpus/${entry.$1}')
            .readAsBytes();
        final digest = sha256.convert(bytes).toString();
        expect(
          digest,
          samples.singleWhere(
            (sample) => sample['filename'] == entry.$1,
          )['sha256'],
        );
        final document = await PdfRuntime.instance.open(bytes, digest);
        addTearDown(document.dispose);
        final text = await document.text(entry.$2);
        expect(text.status, entry.$3);
        final image = await document.render(entry.$2, 360);
        expect(image.width, 360);
        expect(image.bgra.any((value) => value < 200), isTrue);
        stdout.writeln(
          jsonEncode({
            'source': entry.$1,
            'page': entry.$2,
            'textStatus': text.status.name,
            'textCharacters': text.text.length,
            'reason': text.reason,
          }),
        );
      },
    );
  }
}
