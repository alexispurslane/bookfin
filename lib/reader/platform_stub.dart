import '../catalog/model.dart';
import '../downloads/downloads.dart';
import 'document.dart';
import 'epub/publication.dart';

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
