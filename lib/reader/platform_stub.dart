import '../catalog/model.dart';
import 'document.dart';
import 'epub/publication.dart';

Future<ReaderDocument> loadReadingDocument(Uri uri, SourceFile source) async =>
    throw const FormatException(
      'Ebook reading is available in the Android app.',
    );

Future<Publication> loadPublication(Uri uri) async =>
    throw const FormatException(
      'EPUB reading is available in the Android app.',
    );
