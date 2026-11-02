import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_epub_viewer/src/server/epub_book_server.dart';
import 'package:flutter_epub_viewer/src/server/epub_zip.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => EpubBookServer.debugUseInterception = true);
  tearDown(() => EpubBookServer.debugUseInterception = null);

  test('unintended remote image requests receive an explicit denial', () async {
    final response = await EpubBookServer.instance.intercept(
      Uri.parse('https://invalid.example/track.png'),
    );
    expect(
      response,
      isNotNull,
      reason: 'null delegates the remote request to the WebView',
    );
    expect(response!.statusCode, 403);
  });

  test('active and remote SVG attributes never reach the image renderer', () async {
    const svg =
        '<svg xmlns="http://www.w3.org/2000/svg" onload="alert(1)"><image href="https://invalid.example/track.png"/></svg>';
    final bytes = ZipEncoder().encode(
      Archive()..addFile(ArchiveFile.string('active.svg', svg)),
    );
    final base = await EpubBookServer.instance.register(
      await EpubZip.openBytes(Uint8List.fromList(bytes)),
    );
    try {
      final response = await EpubBookServer.instance.intercept(
        base.resolve('active.svg'),
      );
      final body = utf8.decode(response!.body);
      expect(body, isNot(contains('onload')));
      expect(body, isNot(contains('https://invalid.example')));
    } finally {
      await EpubBookServer.instance.unregister(base);
    }
  });
}
