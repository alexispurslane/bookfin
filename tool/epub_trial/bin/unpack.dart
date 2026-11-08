// Writes each EPUB's admitted publication (the files that Bookfin's reader
// shows, after its sanitizer) into a directory, for the epub.js side of the
// fidelity comparison. Each style sheet is the book's own text, as in the
// trial renderer's TrialBook, because the sanitizer empties every
// Standard Ebooks sheet.
//
// dart run bin/unpack.dart <out directory> <book.epub>...
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_epub_viewer/publication.dart';

void main(List<String> arguments) {
  final out = Directory(arguments.first);
  for (final path in arguments.skip(1)) {
    final name = path.split('/').last.replaceAll('.epub', '');
    final bytes = File(path).readAsBytesSync();
    final publication = Publication.admit(bytes);
    final archive = ZipDecoder().decodeBytes(bytes);
    final root = Directory('${out.path}/$name');
    if (root.existsSync()) root.deleteSync(recursive: true);
    for (final entry in publication.resources.entries) {
      final original = publication.mediaTypes[entry.key] == 'text/css'
          ? archive.findFile(entry.key)?.readBytes()
          : null;
      File('${root.path}/${entry.key}')
        ..createSync(recursive: true)
        ..writeAsBytesSync(original ?? Uint8List.fromList(entry.value));
    }
    File('${root.path}/bookfin-trial.txt').writeAsStringSync(
      [publication.packagePath, ...publication.spine].join('\n'),
    );
    stdout.writeln(
      '$name: ${publication.spine.length} sections, '
      'warnings: ${publication.warnings}',
    );
  }
}
