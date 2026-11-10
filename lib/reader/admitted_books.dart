// The admitted books that Bookfin keeps beside their downloads (t7-rcyp).
//
// Admission unzips a book, checks and sanitizes each resource, and hashes
// what it admitted. Its output depends only on the downloaded file, the
// reading policy and the admission code, so Bookfin admits a downloaded file
// once and keeps the result with the download's derived files. Removing the
// download removes it.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../downloads/derived_files.dart';
import 'epub/publication.dart';

/// The admitted book that Bookfin keeps for each download.
///
/// The record is the file `publication` in the download's admitted
/// directory: a key line, then the bytes of [Publication.encode]. The key
/// names the downloaded file's digest, the reading policy and
/// [Publication.revision]. A download keeps one record, so a new key
/// replaces the old record.
abstract final class AdmittedBooks {
  /// The publication of the downloaded file [original], whose bytes have the
  /// SHA-256 [digest], read under the reading policy [policy].
  ///
  /// When the kept record has this key, the publication comes from it, and
  /// [admit] does not run. Otherwise [admit] admits the book, and its
  /// publication replaces the kept record. A kept record that cannot be read
  /// is set aside as `publication.unreadable`, and the book admits in full.
  /// A record that cannot be written costs one more full admission at the
  /// next open, so it does not fail the open.
  ///
  /// It reads, decodes and encodes the record in the calling isolate, so
  /// call it in a worker.
  static Future<Publication> open(
    File original,
    String digest,
    String policy,
    Future<Publication> Function() admit,
  ) async {
    final directory = DerivedBookFiles.admittedDirectory(original);
    final record = File('${directory.path}/publication');
    final key = utf8.encode(jsonEncode([Publication.revision, policy, digest]));
    if (await _kept(record, key) case final kept?) return kept;
    final publication = await admit();
    await _keep(record, key, publication);
    return publication;
  }

  /// The publication of [record] when its key is [key], or null. A record
  /// with another key is a book that changed or an older policy, which the
  /// next write replaces. A record that cannot be read is set aside.
  static Future<Publication?> _kept(File record, List<int> key) async {
    final Uint8List bytes;
    try {
      if (await FileSystemEntity.type(record.path, followLinks: false) !=
          FileSystemEntityType.file) {
        return null;
      }
      bytes = await record.readAsBytes();
    } on FileSystemException {
      return null;
    }
    try {
      final end = bytes.indexOf(0x0a);
      if (end < 0 || end > 1024) {
        throw const FormatException('The record has no key.');
      }
      final kept = utf8.decode(Uint8List.sublistView(bytes, 0, end));
      if (jsonDecode(kept) is! List) {
        throw const FormatException('The record has no key.');
      }
      if (!listEquals(utf8.encode(kept), key)) return null;
      return Publication.decode(Uint8List.sublistView(bytes, end + 1));
    } on FormatException {
      try {
        await record.rename('${record.path}.unreadable');
      } on FileSystemException {
        // The next write replaces the record.
      }
      return null;
    }
  }

  /// Writes [publication] under [key] to [record] with
  /// [DerivedBookFiles.write], so a process that dies during the write
  /// leaves the old record whole.
  static Future<void> _keep(
    File record,
    List<int> key,
    Publication publication,
  ) async {
    try {
      await DerivedBookFiles.write(
        record,
        (BytesBuilder(copy: false)
              ..add(key)
              ..addByte(0x0a)
              ..add(publication.encode()))
            .takeBytes(),
      );
    } on FileSystemException {
      // The next open admits the book again and tries again.
    }
  }
}
