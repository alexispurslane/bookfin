import 'text_outline.dart';

/// This platform supplies no ebook files, so it cannot measure a PDF outline.
Future<TextOutline> measurePdfOutline(String path) async =>
    throw UnsupportedError('PDF outlines need the Android app.');
