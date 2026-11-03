import 'dart:io';

/// The on-disk derived-book layout. Downloads owns the source directory and
/// orders reading/conversion before removal through readLocalFile.
class DerivedBookFiles {
  static Directory ocrDirectory(File original) =>
      Directory('${original.parent.path}/.bookfin-ocr');
  static Directory mobiDirectory(File original) =>
      Directory('${original.parent.path}/.bookfin-mobi');

  static Directory _directory(Directory source) =>
      mobiDirectory(File('${source.path}/complete'));

  /// Actual regular derived-file bytes; symbolic links never contribute.
  static int bytes(Directory source) {
    try {
      var total = 0;
      for (final directory in [
        _directory(source),
        ocrDirectory(File('${source.path}/complete')),
      ]) {
        if (FileSystemEntity.typeSync(directory.path, followLinks: false) !=
            FileSystemEntityType.directory) {
          continue;
        }
        var bytes = 0;
        for (final entry in directory.listSync(
          recursive: true,
          followLinks: false,
        )) {
          if (entry is File &&
              FileSystemEntity.typeSync(entry.path, followLinks: false) ==
                  FileSystemEntityType.file) {
            bytes += entry.lengthSync();
          }
        }
        total += bytes;
      }
      return total;
    } on FileSystemException {
      // A status query can overlap filesystem completion of an owned removal.
      return 0;
    }
  }

  /// Remove only the derived subtree, without traversing symbolic links.
  static Future<void> remove(Directory source) async {
    for (final directory in [
      _directory(source),
      ocrDirectory(File('${source.path}/complete')),
    ]) {
      if (await FileSystemEntity.type(directory.path, followLinks: false) ==
          FileSystemEntityType.directory) {
        await directory.delete(recursive: true);
      }
    }
  }
}
