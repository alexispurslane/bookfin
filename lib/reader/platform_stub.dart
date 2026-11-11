import '../catalog/model.dart';
import '../downloads/downloads.dart';
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

/// No ebook loads on this platform, so no files that they write.
Future<void> derivedFilesWritten(VerifiedFile original) async {}

/// No ebook downloads on this platform, so no text outlines.
Future<TextOutline> measureDownloadedOutline(
  VerifiedFile original,
  SourceFile source,
) async => throw UnsupportedError('Ebook outlines need the Android app.');
