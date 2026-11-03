import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/ocr.dart';
import 'package:bookfin/reader/pdf.dart';
import 'package:bookfin/reader/platform_io.dart';
import 'package:bookfin/reader/session.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:pdfrx_engine/pdfrx_engine.dart';

import '../playback/playback_test.dart' show account, LocalFiles, MemoryResume;
import 'pdf_document_test.dart' show pdfSource;
import 'pdf_session_test.dart' show book, edition;

Uint8List imagePdf(image.Image scan) {
  final rgb = scan.getBytes(order: image.ChannelOrder.rgb);
  final pixels = zlib.encode(rgb);
  final output = BytesBuilder();
  void text(String value) => output.add(ascii.encode(value));
  text('%PDF-1.4\n');
  final offsets = <int>[0];
  void object(int number, String value) {
    offsets.add(output.length);
    text('$number 0 obj\n$value\nendobj\n');
  }

  object(1, '<< /Type /Catalog /Pages 2 0 R >>');
  object(2, '<< /Type /Pages /Kids [3 0 R] /Count 1 >>');
  object(
    3,
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${scan.width} ${scan.height}] /Resources << /XObject << /Scan 4 0 R >> >> /Contents 5 0 R >>',
  );
  offsets.add(output.length);
  text(
    '4 0 obj\n<< /Type /XObject /Subtype /Image /Width ${scan.width} /Height ${scan.height} /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /FlateDecode /Length ${pixels.length} >>\nstream\n',
  );
  output.add(pixels);
  text('\nendstream\nendobj\n');
  final draw = 'q ${scan.width} 0 0 ${scan.height} 0 0 cm /Scan Do Q';
  object(5, '<< /Length ${draw.length} >>\nstream\n$draw\nendstream');
  final xref = output.length;
  text('xref\n0 6\n0000000000 65535 f \n');
  for (final offset in offsets.skip(1)) {
    text('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  text('trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n');
  return output.takeBytes();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Pdfrx.pdfiumModulePath = Platform.environment['PDFIUM_LIBRARY'];
  Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;
  test('the actual host engine and selected model supply text to a real scanned PDF and its owned cache', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final parent = await Directory('.cache/ocr/native-test').absolute
        .create(recursive: true);
    final root = await parent.createTemp('run-');
    final png = await File('test/reader/fixtures/ocr/generated-english.png')
        .readAsBytes();
    expect(
      sha256.convert(png).toString(),
      '30fce43633b99aa18db29680ee9ed9ebd1733c97eca7ee6c3055eaeddd1d6af6',
    );
    final referenceBytes = await File(
      'test/reader/fixtures/ocr/generated-english.txt',
    ).readAsBytes();
    expect(
      sha256.convert(referenceBytes).toString(),
      '723d33dff412736715fc684a7393469a200e86f58fc4042df3bf0142010c564d',
    );
    final reference = utf8
        .decode(referenceBytes)
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
    final original = await File('${root.path}/complete')
        .writeAsBytes(imagePdf(image.decodePng(png)!));
    final model = Platform.environment['BOOKFIN_OCR_MODEL']!;
    expect(
      sha256.convert(await File(model).readAsBytes()).toString(),
      '7d4322bd2a7749724879683fc3912cb542f19906c83bcc1a52132556427170b2',
    );
    await Link('${root.path}/eng.traineddata').create(model);
    const channel = MethodChannel('bookfin/ocr');
    var calls = 0;
    String? boundaryError;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method != 'recognize') return null;
          calls++;
          try {
            final args = call.arguments as Map;
            final width = args['width'] as int;
            final height = args['height'] as int;
            final bgra = args['bgra'] as Uint8List;
            final rgb = Uint8List(width * height * 3);
            for (var pixel = 0; pixel < width * height; pixel++) {
              rgb[pixel * 3] = bgra[pixel * 4 + 2];
              rgb[pixel * 3 + 1] = bgra[pixel * 4 + 1];
              rgb[pixel * 3 + 2] = bgra[pixel * 4];
            }
            final raster = File('${root.path}/page.png');
            await raster.writeAsBytes(
              image.encodePng(
                image.Image.fromBytes(
                  width: width,
                  height: height,
                  bytes: rgb.buffer,
                  numChannels: 3,
                  order: image.ChannelOrder.rgb,
                ),
              ),
            );
            final result = await Process.run(
              'tesseract',
              [
                raster.path,
                'stdout',
                '--tessdata-dir',
                root.path,
                '-l',
                'eng',
                '--oem',
                '1',
                '--psm',
                '3',
                '-c',
                'tessedit_create_hocr=1',
              ],
              environment: {'OMP_THREAD_LIMIT': '1'},
              stdoutEncoding: null,
              stderrEncoding: null,
            );
            final hocr = utf8.decode(result.stdout as List<int>);
            expect(
              result.exitCode,
              0,
              reason: utf8.decode(
                result.stderr as List<int>,
                allowMalformed: true,
              ),
            );
            try {
              decodeRecognizedPage(hocr);
            } on Exception catch (error) {
              boundaryError = '$error\n$hocr';
            }
            return hocr;
          } on Object catch (error) {
            boundaryError = error.toString();
            rethrow;
          }
        });
    final downloads = LocalFiles()..files[pdfSource.key] = original.uri;
    final reader = ReaderSession(
      downloads: downloads,
      store: MemoryResume(),
      load: loadPublication,
      loadDocument: (uri, source) =>
          loadReadingDocument(uri, source, textSupply: BundledEnglishText()),
    );
    try {
      await reader.bind(account(), [book]);
      await reader.open(book, edition);
      final pdf = reader.document! as PdfBook;
      final recognized = await pdf.text(1);
      expect(
        recognized.status,
        PdfTextStatus.candidate,
        reason: '${recognized.reason}\ncalls=$calls\n$boundaryError',
      );
      expect(recognized.text.trim().replaceAll(RegExp(r'\s+'), ' '), reference);
      reader.acceptAddress(
        reader.token,
        PdfAddress(1, recognized.source.indexOf('Original pages')),
      );
      await reader.addBookmark(title: 'Recognized source page');
      await reader.flush();
      reader.closeView(reader.token);
      await reader.open(book, edition);
      expect((reader.initialAddress as PdfAddress).sourcePage, 1);
      expect(reader.bookmarks.single.title, 'Recognized source page');
      expect(
        (await (reader.document! as PdfBook).text(1)).text,
        recognized.text,
      );
      expect(calls, 1);
      reader.checkInvariants();
      final version = await Process.run('tesseract', ['--version']);
      debugPrint(
        'Actual host engine (not Android acceptance): ${version.stdout.toString().split('\n').take(2).join('; ')}; exact selected English-fast model; full generated-English reference matches.',
      );
    } finally {
      reader.dispose();
      await PdfRuntime.instance.shutdown();
      downloads.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      debugDefaultTargetPlatformOverride = null;
      await root.delete(recursive: true);
    }
  });
}
