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
import '../downloads/downloads.dart';
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
///
/// Downloads prepares each saved ebook when its download completes and at
/// launch ([prepare], boo-sy2d), so the first open of a book normally
/// finds its record kept, also after an update that changed
/// [Publication.revision].
abstract final class AdmittedBooks {
  /// What [use] gives for the publication of the downloaded file
  /// [original], read under the reading policy [policy].
  ///
  /// One worker isolate reads the publication from the kept record, or
  /// admits the book with [admit], as [read] does, and runs [use] on it.
  /// Only the result of [use] comes back. When the book was admitted, a
  /// worker of its own writes its record after, as [keep] does, under a
  /// hold of the download ([VerifiedFile.hold]), so that a removal of the
  /// download waits for it. When [use] throws, the load worker writes the
  /// record before the error leaves it, so the next load does not admit the
  /// book again. The load first waits for the record writes of [original]
  /// that an earlier load or a [prepare] started ([written]).
  ///
  /// [admit] and [use] run in the worker, so they must capture only values
  /// that can be sent to another isolate.
  static Future<T> load<T>(
    VerifiedFile original,
    String policy,
    Future<Publication> Function() admit,
    T Function(Publication publication) use,
  ) async {
    final file = File.fromUri(original.uri);
    await written(file);
    final path = file.path;
    final digest = original.digest;
    final (result, record) = await Isolate.run(() async {
      final (publication, record) = await read(
        File(path),
        digest,
        policy,
        admit,
      );
      final T result;
      try {
        result = use(publication);
      } catch (_) {
        if (record != null) await keep(record);
        rethrow;
      }
      return (result, record);
    });
    if (record != null) unawaited(_keepLater(record, original));
    return result;
  }

  /// Makes the kept record of the downloaded file [original], under the
  /// reading policy [policy], current, so that the next [load] reads it.
  ///
  /// When the kept record's key names [original]'s digest, [policy] and
  /// [Publication.revision], nothing more runs: the check reads only the
  /// key. Otherwise one worker isolate admits the book with [admit] and
  /// writes its record, as [load] and [keep] do, and the publication stays
  /// in the worker. A [load] of [original] that starts meanwhile waits for
  /// the write ([written]), and reads the record. Throws what [admit]
  /// throws, and then writes no record, but keeps the key of the failure
  /// beside it: the next preparation with that key does nothing, as for a
  /// damaged book or another format, and a [load] still admits the book.
  ///
  /// It writes beside the download, so it runs under a hold of the download
  /// ([VerifiedFile.hold]). [admit] runs in the worker, so it must capture
  /// only values that can be sent to another isolate.
  static Future<void> prepare(
    VerifiedFile original,
    String policy,
    Future<Publication> Function() admit,
  ) {
    final file = File.fromUri(original.uri);
    final record = _recordOf(file);
    final failed = File('${record.parent.path}/failed');
    final key = _keyOf(policy, original.digest);
    final path = file.path;
    final digest = original.digest;
    // The preparation is one write of the record from its first step, so a
    // load that starts during the key check waits for it too.
    return original.hold(
      () => _track(record.path, () async {
        if (await _keyed(record, key) || await _keyed(failed, key)) return;
        try {
          await Isolate.run(() async {
            final (_, admitted) = await read(File(path), digest, policy, admit);
            if (admitted != null) await keep(admitted);
          });
        } catch (_) {
          try {
            await DerivedBookFiles.write(failed, [...key, 0x0a]);
          } on FileSystemException {
            // The next preparation tries the book again.
          }
          rethrow;
        }
      }),
    );
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
    final key = _keyOf(policy, digest);
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
  /// the load of [original] that admitted the book returned, under a hold
  /// of the download. [written] completes once the write ends.
  static Future<void> _keepLater(
    AdmittedRecord record,
    VerifiedFile original,
  ) => original.hold(() => _track(record._path, () => _keepInWorker(record)));

  /// Runs [write], a write of the record at [path], after the writes of it
  /// before it, so that [written] waits for it. Gives the end of [write],
  /// with its error.
  static Future<void> _track(String path, Future<void> Function() write) {
    final done = (_writes[path] ?? Future.value()).then((_) => write());
    final ended = _writes[path] = done.then<void>(
      (_) {},
      onError: (Object _) {},
    );
    unawaited(
      ended.whenComplete(() {
        if (identical(_writes[path], ended)) _writes.remove(path);
      }),
    );
    return done;
  }

  /// Writes [record] in a worker isolate of its own. It is static, so that
  /// the worker's closure holds only [record]. A worker that cannot start
  /// costs one more full admission at the next open, as a failed write
  /// does, so it does not fail either.
  static Future<void> _keepInWorker(AdmittedRecord record) =>
      Isolate.run(() => keep(record)).catchError((Object _) {});

  /// Completes once the record writes of [original] that [load] or
  /// [prepare] started in this isolate ended.
  static Future<void> written(File original) =>
      _writes[_recordOf(original).path] ?? Future.value();

  /// The record writes that [load] and [prepare] started, by record path.
  static final _writes = <String, Future<void>>{};

  /// The key line of a record of a download whose bytes have the SHA-256
  /// [digest], read under [policy].
  static List<int> _keyOf(String policy, String digest) =>
      utf8.encode(jsonEncode([Publication.revision, policy, digest]));

  /// Whether [record] begins with the key line [key]. It reads only the
  /// key, so a record whose later bytes are damaged counts as kept: the
  /// next [load] sets it aside and admits the book in full.
  static Future<bool> _keyed(File record, List<int> key) async {
    try {
      final file = await record.open();
      try {
        final start = await file.read(key.length + 1);
        return start.length == key.length + 1 &&
            start.last == 0x0a &&
            listEquals(Uint8List.sublistView(start, 0, key.length), key);
      } finally {
        await file.close();
      }
    } on FileSystemException {
      return false;
    }
  }

  /// The record of the download [original].
  static File _recordOf(File original) =>
      File('${DerivedBookFiles.admittedDirectory(original).path}/publication');

  /// The publication of [record] when its key is [key], or null. A record
  /// with another key is a book that changed or an older policy, which the
  /// next write replaces. A record that cannot be read is set aside.
  ///
  /// The publication reads its images and fonts from [record] later, while
  /// the record still begins with its key line.
  static Future<Publication?> _kept(File record, List<int> key) async {
    final RandomAccessFile file;
    try {
      if (await FileSystemEntity.type(record.path, followLinks: false) !=
          FileSystemEntityType.file) {
        return null;
      }
      file = await record.open();
    } on FileSystemException {
      return null;
    }
    try {
      try {
        final start = await file.read(1025);
        final end = start.indexOf(0x0a);
        if (end < 0) throw const FormatException('The record has no key.');
        final kept = utf8.decode(Uint8List.sublistView(start, 0, end));
        if (jsonDecode(kept) is! List) {
          throw const FormatException('The record has no key.');
        }
        if (!listEquals(utf8.encode(kept), key)) return null;
        await file.setPosition(end + 1);
        return await Publication.decode(
          file,
          path: record.path,
          head: Uint8List.sublistView(start, 0, end + 1),
        );
      } finally {
        await file.close();
      }
    } on FormatException {
      try {
        await record.rename('${record.path}.unreadable');
      } on FileSystemException {
        // The next write replaces the record.
      }
      return null;
    } on FileSystemException {
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
