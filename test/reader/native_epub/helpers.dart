import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bookfin/reader/native_epub/layout.dart';

bool _fontLoaded = false;

/// Loads the reader's font under the family that [PageTheme] uses.
Future<void> loadReaderFont() async {
  if (_fontLoaded) return;
  final bytes = File('assets/fonts/SourceSerif4.ttf').readAsBytesSync();
  await ui.loadFontFromList(bytes, fontFamily: 'Source Serif 4');
  _fontLoaded = true;
}

/// A made-up section whose body is [body], styled by [css].
SectionInput section(
  String body, {
  String css = '',
  Map<String, Uint8List> files = const {},
}) => SectionInput(
  'text/one.xhtml',
  '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Test</title>'
      '<style>$css</style></head><body>$body</body></html>',
  (path) => files[path],
);

/// [body] laid out on a page of [theme].
Future<ChapterLayout> lay(
  String body, {
  String css = '',
  PageTheme theme = const PageTheme(),
  Map<String, Uint8List> files = const {},
}) async {
  await loadReaderFont();
  final prepared = await prepareSection(
    section(body, css: css, files: files),
    theme,
  );
  return layoutSection(prepared, theme);
}

/// [count] made-up sentences about a harbour.
String prose(int count, [String label = 'Harbour']) => List.generate(
  count,
  (index) =>
      '$label passage ${index + 1}. The reader followed the shoreline and '
      'watched the small boats return.',
).join(' ');

/// The test books in .cache/epub-trial/books, which the trial downloads
/// from Standard Ebooks and Project Gutenberg. Empty when they are absent.
List<File> trialBooks() {
  final directory = Directory('.cache/epub-trial/books');
  if (!directory.existsSync()) return [];
  return directory
      .listSync()
      .whereType<File>()
      .where((file) => file.path.endsWith('.epub'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

String bookName(File file) =>
    file.uri.pathSegments.last.replaceAll('.epub', '');
