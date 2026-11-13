import '../catalog/model.dart';
import '../downloads/downloads.dart';
import '../speech/book_search.dart';
import 'document.dart';
import 'epub/publication.dart';
import 'text_outline.dart';

Future<ReaderDocument> loadReadingDocument(
  VerifiedFile original,
  SourceFile source,
) async => throw const FormatException(
  'Ebook reading is available in the Android app.',
);

Future<Publication> loadPublication(VerifiedFile original) async =>
    throw const FormatException(
      'EPUB reading is available in the Android app.',
    );

/// No ebook loads on this platform, so none needs preparation.
Future<void> prepareDownloadedBook(
  VerifiedFile original,
  SourceFile source,
) async {}

/// No ebook downloads on this platform, so no words for speech.
Future<ReadBook?> bookWordsReader(
  VerifiedFile original,
  SourceFile source,
  TextOutline outline,
) async => null;

/// No ebook downloads on this platform, so no text outlines.
Future<TextOutline> measureDownloadedOutline(
  VerifiedFile original,
  SourceFile source,
) async => throw UnsupportedError('Ebook outlines need the Android app.');
