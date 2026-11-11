// The admitted books that Bookfin keeps beside their downloads (t7-rcyp).
//
// Admission unzips a book, checks and sanitizes each resource, and hashes
// what it admitted. Its output depends only on the downloaded file, the
// reading policy and the admission code, so Bookfin admits a downloaded file
// once and keeps the result with the download's derived files. Removing the
// download removes it.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

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
///
/// A load of a book does not wait for its record's write (boo-yjq6): [load]
/// gives its result as soon as the book is read or admitted, and a worker
/// of its own writes the record after. An open of the same download waits
/// for that write ([written]), so it reads the record instead of admitting
/// the book again.
abstract final class AdmittedBooks {
  /// What [use] gives for the publication of the downloaded file
  /// [original], whose bytes have the SHA-256 [digest], read under the
  /// reading policy [policy].
  ///
  /// One worker isolate reads the publication from the kept record, or
  /// admits the book with [admit], as [read] does, and runs [use] on it.
  /// Only the result of [use] comes back. When the book was admitted, a
  /// worker of its own writes its record after, as [keep] does. The load
  /// first waits for the record writes of [original] that an earlier load
  /// started ([written]).
  ///
  /// [admit] and [use] run in the worker, so they must capture only values
  /// that can be sent to another isolate.
  static Future<T> load<T>(
    File original,
    String digest,
    String policy,
    Future<Publication> Function() admit,
    T Function(Publication publication) use,
  ) async {
    await written(original);
    final path = original.path;
    final (result, record) = await Isolate.run(() async {
      final (publication, record) = await read(
        File(path),
        digest,
        policy,
        admit,
      );
      return (use(publication), record);
    });
    if (record != null) _keepLater(record);
    return result;
  }

  /// The publication of the downloaded file [original], whose bytes have the
  /// SHA-256 [digest], read under the reading policy [policy], and the
  /// record to keep for it, or null when the record is kept.
  ///
  /// When the kept record has this key, the publication comes from it, and
  /// [admit] does not run. Otherwise [admit] admits the book, and the record
  /// that [keep] writes replaces the kept one. A kept record
  /// that cannot be read is set aside as `publication.unreadable`, and the
  /// book admits in full. A record that is never written costs one more full
  /// admission at the next open.
  ///
  /// It reads, decodes and encodes the record in the calling isolate, so
  /// call it in a worker. The record moves to another isolate without a
  /// copy.
  static Future<(Publication, AdmittedRecord?)> read(
    File original,
    String digest,
    String policy,
    Future<Publication> Function() admit,
  ) async {
    final record = _recordOf(original);
    final key = utf8.encode(jsonEncode([Publication.revision, policy, digest]));
    if (await _kept(record, key) case final kept?) return (kept, null);
    final publication = await admit();
    return (
      publication,
      AdmittedRecord._(
        record.path,
        TransferableTypedData.fromList([
          Uint8List.fromList(key),
          Uint8List.fromList(const [0x0a]),
          ...publication.encode(),
        ]),
      ),
    );
  }

  /// Writes [record] with [DerivedBookFiles.write], so a process that dies
  /// during the write leaves the old record whole. A record that cannot be
  /// written costs one more full admission at the next open, so the write
  /// does not fail. A record can be written once.
  static Future<void> keep(AdmittedRecord record) async {
    try {
      await DerivedBookFiles.write(
        File(record._path),
        record._bytes.materialize().asUint8List(),
      );
    } on FileSystemException {
      // The next open admits the book again and tries again.
    }
  }

  /// Writes [record] in a worker isolate of its own, as [keep] does, after
  /// the load that admitted the book returned. [written] completes once the
  /// write ends.
  static void _keepLater(AdmittedRecord record) {
    final path = record._path;
    final writes = _writes[path] = (_writes[path] ?? Future.value()).then(
      (_) => _keepInWorker(record),
    );
    unawaited(
      writes.whenComplete(() {
        if (identical(_writes[path], writes)) _writes.remove(path);
      }),
    );
  }

  /// Writes [record] in a worker isolate of its own. It is static, so that
  /// the worker's closure holds only [record].
  static Future<void> _keepInWorker(AdmittedRecord record) =>
      Isolate.run(() => keep(record));

  /// Completes once the record writes of [original] that [load] started in
  /// this isolate ended.
  static Future<void> written(File original) =>
      _writes[_recordOf(original).path] ?? Future.value();

  /// The record writes that [load] started, by record path.
  static final _writes = <String, Future<void>>{};

  /// The record of the download [original].
  static File _recordOf(File original) =>
      File('${DerivedBookFiles.admittedDirectory(original).path}/publication');

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
}

/// The record of an admitted book that is not kept yet: what
/// [AdmittedBooks.keep] writes.
final class AdmittedRecord {
  AdmittedRecord._(this._path, this._bytes);

  final String _path;
  final TransferableTypedData _bytes;
}
