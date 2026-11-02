import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_epub_viewer/src/server/epub_book_server.dart';
import 'package:flutter_epub_viewer/src/server/epub_zip.dart';
import 'package:flutter_test/flutter_test.dart';

final work = Directory(Platform.environment['NAVIGATOR_WORK']!);
final evidence = Directory(Platform.environment['NAVIGATOR_EVIDENCE']!);

Future<Uri> registerFile(String filename) async {
  EpubBookServer.debugUseInterception = true;
  return EpubBookServer.instance.register(
    await EpubZip.openFile('${work.path}/$filename'),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => EpubBookServer.debugUseInterception = null);

  test(
    'converted KF8 chapter, SVG and JPEG keep their own archive paths',
    () async {
      final base = await registerFile('converted/alice.epub');
      try {
        final server = EpubBookServer.instance;
        final chapter = await server.intercept(
          base.resolve('OEBPS/part00000.html'),
        );
        final svg = await server.intercept(base.resolve('OEBPS/flow00004.svg'));
        final jpeg = await server.intercept(
          base.resolve('OEBPS/resource00000.jpg'),
        );
        expect(chapter!.statusCode, 200);
        expect(utf8.decode(chapter.body), contains('flow00004.svg'));
        expect(svg!.contentType, 'image/svg+xml');
        expect(
          utf8.decode(svg.body),
          contains('xlink:href="resource00000.jpg"'),
        );
        expect(jpeg!.contentType, 'image/jpeg');
        expect(
          jpeg.body,
          File('${work.path}/widget-assets/kf8-cover.jpg').readAsBytesSync(),
        );
        expect(
          (await server.intercept(base.resolve('OEBPS/missing.jpg')))!
              .statusCode,
          404,
        );
      } finally {
        await EpubBookServer.instance.unregister(base);
      }
      expect(
        (await EpubBookServer.instance.intercept(
          base.resolve('OEBPS/resource00000.jpg'),
        ))!.statusCode,
        404,
      );
      expect(EpubBookServer.instance.bookCount, 0);
    },
  );

  test(
    'generated EPUB chapter and PNG remain associated without URI flattening',
    () async {
      final base = await registerFile('inputs/river.epub');
      try {
        final server = EpubBookServer.instance;
        final png = await server.intercept(base.resolve('OEBPS/dot.png'));
        final chapter = await server.intercept(
          base.resolve('OEBPS/chapter.xhtml'),
        );
        expect(chapter!.statusCode, 200);
        expect(utf8.decode(chapter.body), contains('dot.png'));
        expect(png!.statusCode, 200);
        expect(png.contentType, 'image/png');
        expect(
          png.body,
          File('${work.path}/widget-assets/dot.png').readAsBytesSync(),
        );
      } finally {
        await EpubBookServer.instance.unregister(base);
      }
    },
  );

  test('nested chapter resources resolve local CSS, PNG and font from their containing resource', () async {
    final base = await registerFile('inputs/semantic.epub');
    try {
      final server = EpubBookServer.instance;
      final chapterUrl = base.resolve('OEBPS/Text/one.xhtml');
      final cssUrl = chapterUrl.resolve('../Styles/book.css');
      final css = await server.intercept(cssUrl);
      final font = await server.intercept(
        cssUrl.resolve('../Fonts/source-serif.woff2'),
      );
      final image = await server.intercept(
        chapterUrl.resolve('../Images/dot.png'),
      );
      expect(utf8.decode(css!.body), contains('../Fonts/source-serif.woff2'));
      expect(font!.contentType, 'font/woff2');
      expect(font.body.sublist(0, 4), ascii.encode('wOF2'));
      expect(image!.contentType, 'image/png');
      expect(
        image.body,
        File('${work.path}/widget-assets/dot.png').readAsBytesSync(),
      );
    } finally {
      await EpubBookServer.instance.unregister(base);
    }
  });

  testWidgets(
    'KF8 JPEG fallback and PNG produce decoded, painted image pixels',
    (tester) async {
      for (final item in [('kf8-cover.jpg', 800, 1104), ('dot.png', 24, 24)]) {
        final content = File('${work.path}/widget-assets/${item.$1}')
            .readAsBytesSync();
        await tester.runAsync(() async {
          final codec = await ui.instantiateImageCodec(content);
          final frame = await codec.getNextFrame();
          expect(frame.image.width, item.$2);
          expect(frame.image.height, item.$3);
          frame.image.dispose();
          codec.dispose();
        });
        final key = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: RepaintBoundary(
                key: key,
                child: SizedBox(
                  width: 160,
                  height: 221,
                  child: Image.memory(content, fit: BoxFit.contain),
                ),
              ),
            ),
          ),
        );
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        });
        await tester.pump();
        expect(tester.takeException(), isNull);
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final painted = await boundary.toImage();
          final pixels = (await painted.toByteData())!.buffer.asUint8List();
          final colors = <int>{};
          for (var offset = 0; offset < pixels.length; offset += 4) {
            colors.add(
              (pixels[offset] << 16) |
                  (pixels[offset + 1] << 8) |
                  pixels[offset + 2],
            );
          }
          if (item.$1 == 'dot.png') {
            final center = (110 * painted.width + 80) * 4;
            expect(pixels.sublist(center, center + 4), [137, 92, 58, 255]);
          } else {
            expect(
              colors.length,
              greaterThan(32),
              reason: 'A blank opaque widget is not a painted cover',
            );
          }
          final png = (await painted.toByteData(
            format: ui.ImageByteFormat.png,
          ))!;
          File('${evidence.path}/${item.$1}.painted.png')
              .writeAsBytesSync(png.buffer.asUint8List());
          painted.dispose();
        });
      }
    },
  );

  test('the original SVG is not a Flutter raster image', () async {
    final svg = File('${work.path}/widget-assets/kf8-original.svg')
        .readAsBytesSync();
    await expectLater(ui.instantiateImageCodec(svg), throwsException);
  });

  test(
    'package interception passes remote requests back to the WebView',
    () async {
      EpubBookServer.debugUseInterception = true;
      final response = await EpubBookServer.instance.intercept(
        Uri.parse('https://invalid.example/track.png'),
      );
      expect(response, isNull);
    },
  );

  test('package resource serving does not sanitize active SVG', () async {
    EpubBookServer.debugUseInterception = true;
    const source =
        '<svg xmlns="http://www.w3.org/2000/svg" onload="alert(1)"><image href="https://invalid.example/track.png"/></svg>';
    final bytes = ZipEncoder().encode(
      Archive()..addFile(ArchiveFile.string('active.svg', source)),
    );
    final base = await EpubBookServer.instance.register(
      await EpubZip.openBytes(Uint8List.fromList(bytes)),
    );
    try {
      final response = await EpubBookServer.instance.intercept(
        base.resolve('active.svg'),
      );
      expect(utf8.decode(response!.body), source);
      File('${evidence.path}/upstream-active-svg.json').writeAsStringSync(
        jsonEncode({
          'status': response.statusCode,
          'mime': response.contentType,
          'sha256': sha256.convert(response.body).toString(),
          'body': source,
          'scope': 'Bytes served by Dart only. No script execution or remote request was attempted.',
        }),
      );
    } finally {
      await EpubBookServer.instance.unregister(base);
    }
  });
}
