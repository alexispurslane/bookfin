import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bookfin/reader/epub/layout.dart';
import 'package:bookfin/reader/epub/prepare.dart';
import 'package:image/image.dart' as img;

bool _fontLoaded = false;

/// Loads the reader's font under the family that layout draws with.
Future<void> loadReaderFont() async {
  if (_fontLoaded) return;
  final bytes = File('assets/fonts/SourceSerif4.ttf').readAsBytesSync();
  await ui.loadFontFromList(bytes, fontFamily: readerFontFamily);
  _fontLoaded = true;
}

/// The WebView reader's default page: 412 × 671 pixels with 20 pixel text,
/// in cream.
const readerPage = PageSettings(
  width: 412,
  height: 671,
  fontSize: 20,
  night: false,
);

/// The width and height of each image of [files] that the image package can
/// read the header of, by path, as the publication gives them to prepare.
Map<String, (int, int)> imageSizes(Map<String, Uint8List> files) => {
  for (final MapEntry(key: path, value: bytes) in files.entries)
    if (img.findDecoderForData(bytes)?.startDecode(bytes) case final info?)
      path: (info.width, info.height),
};

/// A made-up section at spine index 0 whose body is [body], styled by
/// [css], with the images of [files].
SectionSource section(
  String body, {
  String css = '',
  Map<String, Uint8List> files = const {},
}) => SectionSource(
  index: 0,
  path: 'text/one.xhtml',
  xhtml:
      '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Test</title>'
      '<style>$css</style></head><body>$body</body></html>',
  imageSizes: imageSizes(files),
);

/// [body] prepared for [settings].
PreparedSection prepared(
  String body, {
  String css = '',
  PageSettings settings = readerPage,
  Map<String, Uint8List> files = const {},
}) => prepareSections([section(body, css: css, files: files)], settings).single;

/// [body] laid out on a page of [settings].
Future<ChapterLayout> lay(
  String body, {
  String css = '',
  PageSettings settings = readerPage,
  Map<String, Uint8List> files = const {},
}) async {
  await loadReaderFont();
  return layoutSection(
    prepared(body, css: css, settings: settings, files: files),
  );
}

/// [count] made-up sentences about a harbour.
String prose(int count, [String label = 'Harbour']) => List.generate(
  count,
  (index) =>
      '$label passage ${index + 1}. The reader followed the shoreline and '
      'watched the small boats return.',
).join(' ');
