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

  /// The survey of the PDF [original] that the reader keeps (tb-lnak).
  static Directory surveyDirectory(File original) =>
      Directory('${original.parent.path}/.bookfin-survey');

  /// Keeps [bytes] as [file], a file of a derived directory, in place of
  /// the file before it. Gives false, and writes nothing, when something
  /// other than a directory holds the directory's name: it is not a derived
  /// file to replace. Throws a [FileSystemException] when the write fails.
  ///
  /// The directory is made when it is absent, but not its parents, so a
  /// removed download is not made again. The bytes go to a partial file of
  /// their own, which a rename puts over [file]. So a process that dies
  /// during the write leaves the old file whole, and two writes of one file
  /// that overlap leave one of them whole. A partial file that another
  /// process left more than a minute ago is removed: that process was
  /// killed during its write. A partial file of this process belongs to a
  /// write that still runs.
  static Future<bool> write(File file, List<int> bytes) async {
    final directory = file.parent;
    switch (await FileSystemEntity.type(directory.path, followLinks: false)) {
      case FileSystemEntityType.notFound:
        await directory.create();
      case FileSystemEntityType.directory:
        break;
      default:
        return false;
    }
    final partial = File(
      '${file.path}.$pid-${DateTime.now().microsecondsSinceEpoch}.partial',
    );
    try {
      await partial.writeAsBytes(bytes, flush: true);
      await partial.rename(file.path);
    } finally {
      if (await partial.exists()) await partial.delete();
    }
    await _removeKilledPartials(directory);
    return true;
  }

  /// The process id and the time of a partial file's name (see [write]).
  static final _partial = RegExp(r'\.(\d+)-\d+\.partial$');

  /// Removes the partial files in [directory] that other processes left
  /// more than a minute ago (see [write]).
  static Future<void> _removeKilledPartials(Directory directory) async {
    final old = DateTime.now().subtract(const Duration(minutes: 1));
    await for (final entry in directory.list(followLinks: false)) {
      final owner = _partial.firstMatch(entry.path)?[1];
      if (entry is! File || owner == null || int.parse(owner) == pid) {
        continue;
      }
      try {
        if ((await entry.stat()).modified.isBefore(old)) await entry.delete();
      } on FileSystemException {
        // Another write removed it, or the next write tries again.
      }
    }
  }

  /// Every derived directory of the download in [source].
  static List<Directory> _directories(Directory source) {
    final original = File('${source.path}/complete');
    return [
      mobiDirectory(original),
      ocrDirectory(original),
      admittedDirectory(original),
      layoutDirectory(original),
      surveyDirectory(original),
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
