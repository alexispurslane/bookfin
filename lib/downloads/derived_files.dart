import 'dart:io';

/// The on-disk derived-book layout. Downloads owns the source directory and
/// orders reading/conversion before removal through readLocalFile.
class DerivedBookFiles {
  static Directory ocrDirectory(File original) =>
      Directory('${original.parent.path}/.bookfin-ocr');
  static Directory mobiDirectory(File original) =>
      Directory('${original.parent.path}/.bookfin-mobi');

  /// The admitted book that the reader keeps for [original].
  static Directory admittedDirectory(File original) =>
      Directory('${original.parent.path}/.bookfin-admitted');

  /// The page maps that the reader keeps for [original] (t5-4lbx).
  static Directory layoutDirectory(File original) =>
      Directory('${original.parent.path}/.bookfin-layout');

  /// Every derived directory of the download in [source].
  static List<Directory> _directories(Directory source) {
    final original = File('${source.path}/complete');
    return [
      mobiDirectory(original),
      ocrDirectory(original),
      admittedDirectory(original),
      layoutDirectory(original),
    ];
  }

  /// Actual regular derived-file bytes; symbolic links never contribute.
  static Future<int> bytes(Directory source) async {
    try {
      var total = 0;
      for (final directory in _directories(source)) {
        if (await FileSystemEntity.type(directory.path, followLinks: false) !=
            FileSystemEntityType.directory) {
          continue;
        }
        await for (final entry in directory.list(
          recursive: true,
          followLinks: false,
        )) {
          if (entry is File &&
              await FileSystemEntity.type(entry.path, followLinks: false) ==
                  FileSystemEntityType.file) {
            total += await entry.length();
          }
        }
      }
      return total;
    } on FileSystemException {
      // A storage look can overlap filesystem completion of an owned removal.
      return 0;
    }
  }

  /// Remove only the derived subtree, without traversing symbolic links.
  static Future<void> remove(Directory source) async {
    for (final directory in _directories(source)) {
      if (await FileSystemEntity.type(directory.path, followLinks: false) ==
          FileSystemEntityType.directory) {
        await directory.delete(recursive: true);
      }
    }
  }
}
