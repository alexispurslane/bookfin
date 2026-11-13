import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../catalog/jellyfin.dart';
import '../catalog/model.dart';
import 'downloads.dart';
import 'derived_files.dart';

class LocalDownloads extends Downloads {
  LocalDownloads({
    required this.root,
    required this.freeBytes,
    required MediaPolicy policy,
    this.clock = DateTime.now,
    this.prepare,
  }) : super(policy) {
    policy.addListener(_networkChanged);
  }

  /// Prepares each saved file of a text edition for reading, such as by
  /// admitting the ebook and keeping the result beside it: once its
  /// download completes, and once after each restoration of the saved
  /// files, as at launch. Preparations run one at a time, in the
  /// background. Each one runs under a hold of its download
  /// ([VerifiedFile.hold]), so a removal of the download waits for it, and
  /// other reads do not. A preparation that fails changes nothing that
  /// Downloads shows: the reader meets the same failure when it opens the
  /// file. Null prepares nothing.
  final Future<void> Function(VerifiedFile original, SourceFile source)?
  prepare;

  final Directory root;
  final Future<int> Function() freeBytes;
  final DateTime Function() clock;
  JellyfinSession? _session;
  Map<String, SourceFile> _sources = {};
  Map<String, Edition> _editions = {};

  /// The source ids of each bound edition, hashed once per bind.
  Map<String, List<String>> _editionSources = {};
  final Map<String, _Record> _records = {};
  final Set<String> _queued = {};
  Future<void>? _binding;

  /// The catalog right after the latest bind call that waits for a worker
  /// applied its plan.
  Future<_Catalog> _planned = Future.value((generation: 0, account: null));

  /// How many bind calls wait for a plan from a worker isolate.
  int _waitingPlans = 0;
  Future<void>? _worker;
  Future<void> _writes = Future.value();
  Future<void> _commands = Future.value();
  final Set<Future<void>> _operations = {};
  final Map<String, Object> _reading = {};

  /// The work that reads hold ([VerifiedFile.hold]) and that still runs, by
  /// source id. A removal of the source's files waits for it. Invariant
  /// ([checkInvariants]): a source id without held work has no entry.
  final Map<String, Set<Future<void>>> _held = {};

  /// How many removals of each source id began. A read's holds run only
  /// while no removal of its source began since the read started.
  final Map<String, int> _removals = {};

  /// The end of the last preparation that waits or runs ([prepare]).
  Future<void> _preparing = Future.value();
  HttpClient? _client;
  String? _active;
  Completer<void>? _activeStopped;
  String? _signature;
  int _generation = 0;
  int _networkGeneration = 0;
  bool _ready = false;
  bool _disposed = false;
  String? _storageError;
  Object _retainedBinding = Object();
  ValueNotifier<LeftoverFiles>? _leftovers;
  Future<void>? _leftoverReads;
  bool _leftoversStale = false;

  @override
  bool get supported => true;

  // Engine rule 1: callers hash one short string at a time, such as an
  // account key or one source identity. That costs microseconds, far less
  // than a hop to another isolate. Whole-library hashing runs in [_plan].
  static String _hash(String value) =>
      sha256.convert(utf8.encode(value)).toString();
  static String _id(SourceFile source) =>
      _hash(jsonEncode([source.key, source.revision]));
  static final _idPattern = RegExp(r'^[a-f0-9]{64}$');
  bool get _remoteAllowed =>
      _session != null &&
      !_session!.needsSignIn &&
      policy.choose(verifiedLocal: false) == MediaLocation.remote;

  /// The catalog that the latest bind call selects: its generation and its
  /// account. It resolves when that bind applied its plan. Read it when a
  /// call starts.
  Future<_Catalog> get _settled =>
      _waitingPlans == 0 ? Future.value(_catalog) : _planned;

  _Catalog get _catalog =>
      (generation: _generation, account: _session?.scope.key);

  /// Binds the catalog of [session]. The source ids and the signature of a
  /// large library come from one hop to a worker isolate. Plans apply in
  /// call order, and calls made after this one wait for it, so they see this
  /// catalog.
  @override
  Future<void> bind(JellyfinSession? session, List<Book> books) {
    final editions = {
      for (final book in books)
        for (final edition in book.editions) edition.id: edition,
    };
    final account = session?.scope.key;
    // Send only the four facts of each source. Sending the editions would
    // also copy every chapter list, which costs more than hashing here.
    final identities = <Object?>[
      for (final edition in editions.values)
        for (final source in edition.files) ...[
          source.key,
          source.revision,
          source.sizeBytes,
          source.isItemOriginal,
        ],
    ];
    // Restoration waits only for commands accepted before this call. Later
    // commands wait for this binding, so waiting for them would deadlock.
    final accepted = _commands;
    // Engine rule 1: one source id costs about 5 µs and a hop about 180 µs,
    // so a library of fewer than 16 sources binds here, at once, when no
    // earlier plan waits to apply.
    if (_waitingPlans == 0 && identities.length < 16 * 4) {
      final (:ids, :signature) = _plan(account, identities);
      return _apply(session, editions, ids, signature, accepted);
    }
    _waitingPlans++;
    final previous = _planned;
    final plan = _hop(account, identities);
    late final Future<void> binding;
    final applied = () async {
      try {
        await previous;
        final (:ids, :signature) = await plan;
        binding = _apply(session, editions, ids, signature, accepted);
        return _catalog;
      } finally {
        _waitingPlans--;
      }
    }();
    _planned = applied.catchError((Object _) => _catalog);
    return applied.then((_) => binding);
  }

  /// [_plan] in a worker isolate. This function shares no closure context
  /// with an instance, so the hop copies only its arguments.
  static Future<({List<String> ids, String signature})> _hop(
    String? account,
    List<Object?> identities,
  ) => Isolate.run(() => _plan(account, identities));

  /// The id of each source in [identities], which holds four facts per
  /// source: key, revision, size and kind. The signature covers [account],
  /// and each distinct source's id, size and kind, so an unchanged
  /// library skips restoration.
  static ({List<String> ids, String signature}) _plan(
    String? account,
    List<Object?> identities,
  ) {
    final ids = <String>[];
    final distinct = <String, List<Object?>>{};
    for (var at = 0; at < identities.length; at += 4) {
      final id = _hash(jsonEncode([identities[at], identities[at + 1]]));
      ids.add(id);
      distinct[id] = [identities[at + 2], identities[at + 3]];
    }
    final signature = _hash(
      jsonEncode([
        account,
        for (final MapEntry(:key, :value) in distinct.entries) [key, ...value],
      ]),
    );
    return (ids: ids, signature: signature);
  }

  /// Makes the planned catalog current. [ids] holds the source ids of
  /// [editions] in order.
  Future<void> _apply(
    JellyfinSession? session,
    Map<String, Edition> editions,
    List<String> ids,
    String signature,
    Future<void> accepted,
  ) {
    if (_disposed) return Future.value();
    final editionSources = <String, List<String>>{};
    final sources = <String, SourceFile>{};
    var next = 0;
    for (final edition in editions.values) {
      final own = editionSources[edition.id] = ids.sublist(
        next,
        next += edition.files.length,
      );
      for (final (index, source) in edition.files.indexed) {
        sources[own[index]] = source;
      }
    }
    _editions = editions;
    _editionSources = editionSources;
    final accountChanged = _session?.scope.key != session?.scope.key;
    final credentialChanged =
        _session?.credentialIdentity != session?.credentialIdentity;
    if (credentialChanged) {
      _session?.credentialChanges.removeListener(_networkChanged);
      ++_networkGeneration;
      _client?.close(force: true);
    }
    _session = session;
    if (credentialChanged) {
      session?.credentialChanges.addListener(_networkChanged);
    }
    if (_signature == signature) {
      // The same sources can form other editions, which changes their status.
      updateWatches();
      _schedule();
      return _binding ?? Future.value();
    }
    _signature = signature;
    _retainedBinding = Object();
    _ready = false;
    final generation = ++_generation;
    _client?.close(force: true);
    _sources = sources;
    _queued.clear();
    _records.clear();
    _storageError = null;
    final binding = _binding = _restore(generation, session, accepted);
    if (accountChanged) {
      // The last list belongs to the previous account.
      _leftovers?.value = const LeftoverFiles(reading: true);
      policy.resetSession();
    }
    _emit();
    return binding;
  }

  Future<void> _restore(
    int generation,
    JellyfinSession? session,
    Future<void> acceptedCommands,
  ) async {
    // Capture this barrier at bind entry: later commands wait on this binding.
    // Earlier accepted commands must finish all of their account-owned writes.
    await acceptedCommands;
    await _worker;
    await _writes;
    if (_disposed || generation != _generation) return;
    if (session != null) {
      try {
        // Only a source that saved something has a directory, so one listing
        // of the account finds every record to restore.
        final account = _accountDirectory(session.scope.key);
        for (final directory in await _savedDirectories(account)) {
          if (_disposed || generation != _generation) return;
          final id = _name(directory);
          // Earlier versions made a directory for every bound source.
          if (await _removeIfEmpty(directory) || !_sources.containsKey(id)) {
            continue;
          }
          final record = _blank(id);
          final manifest = record.file('record.json');
          if (await _regularFile(manifest)) {
            // Engine rule 1: a manifest is about 200 bytes and decodes in
            // about 10 µs, far less than a hop. File reads separate the
            // decodes, so a large library still never holds a frame.
            try {
              final data = jsonDecode(
                await manifest.readAsString(),
              ) as Map<String, dynamic>;
              if (data['key'] == record.source.key &&
                  data['revision'] == record.source.revision) {
                record.length = data['length'] as int?;
                record.etag = data['etag'] as String?;
                record.digest = data['digest'] as String?;
                record.verified = data['verified'] as String?;
                record.requested = data['requested'] == true;
                record.error = data['error'] as String?;
                record.complete = data['complete'] == true;
              }
            } catch (_) {
              record.error = 'The saved download record is unreadable. Retry this download.';
            }
          }
          if (!record.complete) await _observe(record);
          if (record.complete && !await _verified(record)) {
            await _rejectComplete(record);
          } else {
            record.bytes = record.complete
                ? record.length!
                : await _partialLength(record);
          }
          if (_disposed || generation != _generation) return;
          _records[id] = record;
          if (record.requested && !record.complete && record.error == null) {
            _queued.add(id);
          }
        }
      } catch (_) {
        if (generation == _generation) _storageError = 'Cannot open private download storage. Restart the app or free storage.';
      }
    }
    if (_disposed || generation != _generation) return;
    _ready = true;
    _emit();
    _schedule();
    final texts = _textSources();
    for (final MapEntry(key: id, value: record) in _records.entries) {
      if (record.complete && texts.contains(id)) _prepareLater(record.source);
    }
  }

  Future<void> _safeDirectory(Directory directory) async {
    final type = await FileSystemEntity.type(
      directory.path,
      followLinks: false,
    );
    if (type == FileSystemEntityType.notFound) {
      await directory.create(recursive: true);
    } else if (type != FileSystemEntityType.directory) {
      throw const _MediaError('Download storage is not a private directory.');
    }
  }

  Directory _accountDirectory(String accountKey) =>
      Directory('${root.path}/${_hash(accountKey)}');

  static String _name(Directory directory) =>
      directory.uri.pathSegments.where((part) => part.isNotEmpty).last;

  /// The source directories under [account]. They are none when the root or
  /// the account directory does not exist, because nothing was saved there.
  /// Throws a [StateError] when either one is not a private directory.
  Future<List<Directory>> _savedDirectories(Directory account) async {
    for (final directory in [root, account]) {
      switch (await FileSystemEntity.type(directory.path, followLinks: false)) {
        case FileSystemEntityType.directory:
          continue;
        case FileSystemEntityType.notFound:
          return const [];
        default:
          throw StateError('Cannot read private download storage.');
      }
    }
    return [
      await for (final entity in account.list(followLinks: false))
        if (entity is Directory && _idPattern.hasMatch(_name(entity))) entity,
    ];
  }

  /// Removes [directory] when it holds no entry, and reports whether it did.
  /// The operating system refuses to remove a directory that holds any
  /// entry, so this never deletes a saved file.
  static Future<bool> _removeIfEmpty(Directory directory) async {
    try {
      await directory.delete();
      return true;
    } on FileSystemException {
      return false;
    }
  }

  /// A record of bound source [id] that saved nothing.
  _Record _blank(String id) => _Record(
    id,
    _sources[id]!,
    Directory('${_accountDirectory(_session!.scope.key).path}/$id'),
    _session!.scope.key,
  );

  /// The record of bound source [id]. A source that saved nothing has none
  /// until a command needs one, and gets its directory at its first write.
  _Record _record(String id) => _records[id] ??= _blank(id);

  Future<bool> _containedDirectory(
    Directory directory,
    String accountKey,
  ) async {
    final account = _accountDirectory(accountKey);
    final name = _name(directory);
    if (!_idPattern.hasMatch(name) ||
        directory.path != '${account.path}/$name') {
      return false;
    }
    for (final entry in [root, account, directory]) {
      if (await FileSystemEntity.type(entry.path, followLinks: false) !=
          FileSystemEntityType.directory) {
        return false;
      }
    }
    return true;
  }

  Future<bool> _regularFile(File file) async =>
      _session != null &&
      await _containedDirectory(file.parent, _session!.scope.key) &&
      await FileSystemEntity.type(file.path, followLinks: false) ==
          FileSystemEntityType.file;

  /// Whether the record is usable locally, by the last look at its storage.
  bool _present(_Record record) =>
      record.complete &&
      record.source.isItemOriginal &&
      record.length != null &&
      record.length! > 0 &&
      record.savedLength == record.length &&
      (record.source.sizeBytes == null ||
          record.source.sizeBytes == record.length);

  /// Look at the record's saved files without blocking the UI isolate, and
  /// report whether the facts changed. A look that a newer look or write
  /// overtakes leaves the newer facts.
  Future<bool> _observe(_Record record) async {
    final version = ++record.diskVersion;
    int? savedLength;
    var derivedBytes = 0;
    try {
      if (await _containedDirectory(record.directory, record.accountKey)) {
        final complete = record.file('complete');
        if (await FileSystemEntity.type(complete.path, followLinks: false) ==
            FileSystemEntityType.file) {
          savedLength = await complete.length();
        }
        derivedBytes = await DerivedBookFiles.bytes(record.directory);
      }
    } catch (_) {
      savedLength = null;
      derivedBytes = 0;
    }
    if (record.diskVersion != version ||
        record.savedLength == savedLength &&
            record.derivedBytes == derivedBytes) {
      return false;
    }
    record.savedLength = savedLength;
    record.derivedBytes = derivedBytes;
    return true;
  }

  /// The saved complete file's length, read synchronously for on-demand
  /// invariant checks only.
  int? _savedLength(_Record record) {
    try {
      final account = _accountDirectory(record.accountKey);
      final complete = record.file('complete');
      return [root, account, record.directory].every(
                (entry) =>
                    FileSystemEntity.typeSync(entry.path, followLinks: false) ==
                    FileSystemEntityType.directory,
              ) &&
              FileSystemEntity.typeSync(complete.path, followLinks: false) ==
                  FileSystemEntityType.file
          ? complete.lengthSync()
          : null;
    } catch (_) {
      return null;
    }
  }

  /// Whether the record's saved file still holds the bytes of its digest.
  ///
  /// A digest reads the whole file, which takes seconds for an audiobook.
  /// So a file is read again only when its fingerprint differs from the one
  /// that the record keeps from the last match: after a write or a touch
  /// outside the app. A match records the new fingerprint, so the next look
  /// and the next launch do not read the file again.
  Future<bool> _verified(_Record record) async {
    await _observe(record);
    if (!_present(record) || record.digest == null) return false;
    try {
      final complete = record.file('complete');
      final fingerprint = await _fingerprint(complete);
      if (fingerprint == record.verified) return true;
      if (await _digest(complete.path, record.length!) != record.digest) {
        return false;
      }
      record.verified = fingerprint;
      // A failed save only costs one more read at the next launch.
      unawaited(_save(record).then((_) {}, onError: (Object _) {}));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// The size and the modification time of [file], to the microsecond. Any
  /// write to the file changes the time.
  static Future<String> _fingerprint(File file) async {
    final stat = await file.stat();
    return '${stat.size}:${stat.modified.microsecondsSinceEpoch}';
  }

  /// The SHA-256 digest of the file at [path], which holds [length] bytes.
  /// A worker isolate reads and hashes the file, so its bytes never reach
  /// this isolate. Each file takes one hop: a book costs more than the hop.
  static Future<String> _digest(String path, int length) {
    Future<String> work() async =>
        (await sha256.bind(File(path).openRead()).first).toString();
    // Engine rule 1: hashing under 16 KiB takes less than the 180 µs hop.
    return length < 16 << 10 ? work() : Isolate.run(work);
  }

  Future<void> _rejectComplete(_Record record) async {
    record.complete = false;
    record.bytes = await _partialLength(record);
    if (!record.source.isItemOriginal) {
      record.error =
          'Saved recording identity cannot be verified. Remove it or retry.';
    }
  }

  Future<int> _partialLength(_Record record) async =>
      await _regularFile(record.file('partial'))
      ? await record.file('partial').length()
      : 0;

  /// Reads only memory: storage facts come from the last look at each record.
  @override
  EditionDownload status(Edition edition) {
    final ids = _editionSources[edition.id];
    if (_session == null || ids == null) return const EditionDownload();
    final files = _editions[edition.id]!.files;
    var complete = 0;
    var bytes = 0;
    var unavailableBytes = 0;
    String? error = _storageError;
    var queued = false;
    for (final id in ids) {
      final record = _records[id];
      if (record == null) continue;
      final present = _present(record);
      if (present) complete++;
      if (!present) {
        unavailableBytes += (record.savedLength ?? 0) + record.derivedBytes;
      }
      bytes += present
          ? record.length!
          : record.complete
          ? 0
          : record.bytes;
      error ??= record.error;
      queued |= _queued.contains(record.id);
    }
    final all = files.isNotEmpty && complete == files.length;
    final phase = all
        ? DownloadPhase.downloaded
        : queued
        ? (_remoteAllowed ? DownloadPhase.downloading : DownloadPhase.waiting)
        : error != null
        ? DownloadPhase.failed
        : complete > 0
        ? DownloadPhase.partial
        : DownloadPhase.none;
    return EditionDownload(
      phase: phase,
      completeFiles: complete,
      totalFiles: files.length,
      bytes: bytes,
      unavailableBytes: unavailableBytes,
      totalBytes: files.every((source) => source.sizeBytes != null)
          ? files.fold(0, (total, source) => total! + source.sizeBytes!)
          : null,
      message: error,
    );
  }

  /// The bound source ids of [edition], which must match the active catalog.
  List<String> _current(Edition edition) {
    final current = _editions[edition.id];
    // Engine rule 1: one edition's identity is a few short strings, once per
    // command. Encoding it costs far less than a hop to another isolate.
    String identity(Edition edition) => jsonEncode([
      for (final source in edition.files) [source.key, source.revision],
    ]);
    if (_disposed ||
        _session == null ||
        current == null ||
        identity(current) != identity(edition)) {
      throw StateError('This edition is not in the active account catalog.');
    }
    return _editionSources[edition.id]!;
  }

  @override
  Future<void> request(Edition edition) => _command(() => _request(edition));

  Future<void> _request(Edition edition) async {
    final generation = _generation;
    final ids = _current(edition);
    if (_storageError != null) {
      _emit();
      return;
    }
    for (final id in ids) {
      final record = _record(id);
      final verified = await _verified(record);
      if (_disposed || generation != _generation) return;
      if (verified) continue;
      final bytes = await _partialLength(record);
      if (_disposed || generation != _generation) return;
      record.complete = false;
      record.bytes = bytes;
      record.error = null;
      record.requested = true;
      _queued.add(record.id);
      await _persist(record);
      if (_disposed || generation != _generation) return;
    }
    _emit();
    _schedule();
  }

  @override
  Future<void> cancel(Edition edition) => _command(() => _cancel(edition));

  Future<void> _cancel(Edition edition) async {
    final records = [for (final id in _current(edition)) ?_records[id]];
    final stopped = records.any((record) => record.id == _active)
        ? _activeStopped?.future
        : null;
    for (final record in records) {
      _queued.remove(record.id);
      record.requested = false;
      record.error = null;
      if (_active == record.id) _client?.close(force: true);
    }
    _emit();
    for (final record in records) {
      await _persist(record);
    }
    // A retry or removal must wait for this transfer's file handle to close,
    // not for unrelated editions to finish downloading.
    await stopped;
  }

  @override
  Future<void> remove(Edition edition) {
    try {
      _current(edition).forEach(_beginRemoval);
    } on StateError {
      // The removal command reports it.
    }
    return _command(() => _remove(edition));
  }

  /// Notes that a removal of source [id] began: its reads lose their
  /// ownership, and work that they hold from now on does not run.
  void _beginRemoval(String id) {
    _reading.remove(id);
    _removals[id] = (_removals[id] ?? 0) + 1;
  }

  /// Completes once no work that reads of source [id] hold runs. The
  /// removal of the source began, so no such work starts.
  Future<void> _heldEnded(String id) async {
    _beginRemoval(id);
    // Held work can hold more work before it ends.
    for (
      var held = _held[id]?.toList();
      held != null && held.isNotEmpty;
      held = _held[id]?.toList()
    ) {
      await Future.wait(held);
    }
  }

  Future<void> _remove(Edition edition) async {
    final ids = _current(edition);
    final generation = _generation;
    // Every source gets a record, so removal also finds its older revisions.
    final records = [for (final id in ids) _record(id)];
    await _cancel(edition);
    void guard() {
      if (_disposed || generation != _generation) {
        throw StateError('The active download catalog changed.');
      }
    }

    guard();
    for (final id in ids) {
      await _heldEnded(id);
    }
    guard();
    try {
      for (final record in records) {
        record.complete = false;
        record.bytes = 0;
        for (final directory in await _savedVersions(record)) {
          await _deleteOwnedFiles(directory, guard);
        }
        record.length = null;
        record.etag = null;
        record.digest = null;
      }
    } finally {
      if (generation == _generation) {
        for (final record in records) {
          await _observe(record);
        }
        _emit();
      }
    }
  }

  Future<List<Directory>> _savedVersions(_Record record) async => [
    record.directory,
    for (final directory in await _savedDirectories(
      _accountDirectory(record.accountKey),
    ))
      if (directory.path != record.directory.path &&
          (await _savedIdentity(directory, record.accountKey))?.key ==
              record.source.key)
        directory,
  ];

  Future<({String key, String revision})?> _savedIdentity(
    Directory directory,
    String accountKey,
  ) async {
    if (!await _containedDirectory(directory, accountKey)) return null;
    final id = _name(directory);
    final manifest = File('${directory.path}/record.json');
    try {
      if (await _regularFile(manifest) && await manifest.length() <= 65536) {
        final data = jsonDecode(await manifest.readAsString());
        if (data is Map<String, dynamic> &&
            data['key'] is String &&
            (data['key'] as String).isNotEmpty &&
            data['revision'] is String &&
            (data['revision'] as String).isNotEmpty &&
            id == _hash(jsonEncode([data['key'], data['revision']]))) {
          return (
            key: data['key'] as String,
            revision: data['revision'] as String,
          );
        }
      }
    } catch (_) {}
    return null;
  }

  Future<RetainedDownload?> _storedDownload(
    Directory directory,
    JellyfinSession session,
    Object binding,
  ) async {
    if (!await _containedDirectory(directory, session.scope.key)) return null;
    final id = _name(directory);
    final identity = await _savedIdentity(directory, session.scope.key);
    var bytes = await DerivedBookFiles.bytes(directory);
    for (final name in ['complete', 'partial']) {
      final file = File('${directory.path}/$name');
      if (await _regularFile(file)) bytes += await file.length();
    }
    return RetainedDownload(
      accountKey: session.scope.key,
      binding: binding,
      id: id,
      sourceKey: identity?.key,
      revision: identity?.revision,
      bytes: bytes,
    );
  }

  @override
  Future<List<RetainedDownload>> retainedStorage() async {
    final (:generation, account: _) = await _settled;
    await _binding;
    final session = _session;
    if (_disposed || generation != _generation || session == null) {
      return const [];
    }
    final account = _accountDirectory(session.scope.key);
    final retained = <RetainedDownload>[];
    for (final directory in await _savedDirectories(account)) {
      if (_disposed || generation != _generation) return const [];
      // A bound source owns its directory, so it is never left over.
      if (_sources.containsKey(_name(directory))) continue;
      final saved = await _storedDownload(directory, session, _retainedBinding);
      if (saved != null && saved.bytes > 0 && !_sources.containsKey(saved.id)) {
        retained.add(saved);
      }
    }
    if (_disposed || generation != _generation) return const [];
    retained.sort((first, second) => first.id.compareTo(second.id));
    return List.unmodifiable(retained);
  }

  @override
  ValueListenable<LeftoverFiles> get leftovers {
    if (_leftovers case final leftovers?) return leftovers;
    final leftovers = _leftovers = ValueNotifier(
      const LeftoverFiles(reading: true),
    );
    unawaited(reloadLeftovers());
    return leftovers;
  }

  @override
  Future<void> reloadLeftovers() {
    if (_disposed) return Future.value();
    if (_leftovers == null) {
      leftovers;
      return _leftoverReads!;
    }
    _leftoversStale = true;
    return _leftoverReads ??= _readLeftovers();
  }

  /// Reads the leftover files until no read was asked for during the last
  /// one, and publishes each result. Requests during a read share one more
  /// read. A result for a catalog that a bind replaced is never shown.
  Future<void> _readLeftovers() async {
    try {
      while (_leftoversStale && !_disposed) {
        _leftoversStale = false;
        final (:generation, account: _) = await _settled;
        LeftoverFiles result;
        try {
          result = LeftoverFiles(entries: await retainedStorage());
        } catch (error) {
          result = LeftoverFiles(
            entries: _leftovers!.value.entries,
            error: error,
          );
        }
        if (_disposed) return;
        if (generation != _generation) {
          _leftoversStale = true;
        } else {
          _leftovers!.value = result;
        }
      }
    } finally {
      // Cleared in the same step that ends the loop, so a request after the
      // last check starts a new read.
      _leftoverReads = null;
    }
  }

  @override
  Future<void> removeRetained(RetainedDownload download) {
    if (_idPattern.hasMatch(download.id)) _beginRemoval(download.id);
    return _command(() => _removeRetained(download));
  }

  Future<void> _removeRetained(RetainedDownload download) async {
    final generation = _generation;
    void guard() {
      if (_disposed ||
          generation != _generation ||
          _session?.scope.key != download.accountKey ||
          !identical(_retainedBinding, download.binding) ||
          _sources.containsKey(download.id) ||
          !download.removable ||
          !_idPattern.hasMatch(download.id)) {
        throw StateError(
          'This retained download no longer belongs to this view.',
        );
      }
    }

    guard();
    final directory = Directory(
      '${_accountDirectory(download.accountKey).path}/${download.id}',
    );
    final identity = await _savedIdentity(directory, download.accountKey);
    guard();
    if (identity == null ||
        identity.key != download.sourceKey ||
        identity.revision != download.revision) {
      throw StateError('The saved download identity cannot be verified.');
    }
    await _heldEnded(download.id);
    guard();
    try {
      await _deleteOwnedFiles(directory, guard);
    } finally {
      if (generation == _generation) _emit();
    }
  }

  Future<void> _deleteOwnedFiles(
    Directory directory,
    void Function() guard,
  ) async {
    guard();
    // A source that saved nothing has no directory.
    if (await FileSystemEntity.type(directory.path, followLinks: false) ==
        FileSystemEntityType.notFound) {
      return;
    }
    Future<void> contain() async {
      guard();
      if (_session == null ||
          !await _containedDirectory(directory, _session!.scope.key)) {
        throw StateError('Download storage is no longer a private directory.');
      }
    }

    await contain();
    await DerivedBookFiles.remove(directory);
    for (final name in ['partial', 'complete', 'record.next', 'record.json']) {
      await contain();
      final file = File('${directory.path}/$name');
      if (await _regularFile(file)) {
        guard();
        await file.delete();
      }
    }
    // A directory that still holds a file that the app did not save stays.
    await contain();
    await _removeIfEmpty(directory);
  }

  @override
  Future<T?> readLocalFile<T>(
    SourceFile source,
    Future<T> Function(VerifiedFile original) read, {
    void Function(bool Function() live)? onOwnership,
  }) async {
    final id = _id(source);
    while (true) {
      final settled = _settled;
      T? result;
      var replaced = true;
      // The existing command owner also orders removal and account
      // restoration. A converter must settle before either can reclaim its
      // source directory.
      await _command(() async {
        final generation = _generation;
        final found = await _lookup(id, generation);
        if (found == null) return;
        replaced = false;
        final file = found.file;
        if (file == null) return;
        final token = Object();
        _reading[id] = token;
        onOwnership?.call(
          () =>
              !_disposed &&
              generation == _generation &&
              identical(_reading[id], token),
        );
        final lend = _Lend(id, generation, _removals[id] ?? 0);
        try {
          result = await read(
            VerifiedFile.lent(
              file.uri,
              file.digest,
              hold: (work) => _hold(lend, work),
            ),
          );
        } finally {
          lend.reading = false;
          if (identical(_reading[id], token)) _reading.remove(id);
        }
      });
      // A bind that replaced the catalog skips the command or ends the
      // lookup. Look again in a new command, outside the one that the new
      // binding waits for.
      if (!replaced || !_stillBound((await settled).account, id)) {
        return result;
      }
    }
  }

  /// Runs [work] under [lend], as [VerifiedFile.hold] describes.
  Future<void> _hold(_Lend lend, Future<void> Function() work) {
    if (!lend.reading && lend.holding == 0) {
      throw StateError('A download can be held only while it is lent.');
    }
    if (_disposed ||
        lend.generation != _generation ||
        (_removals[lend.id] ?? 0) != lend.removals) {
      return Future.value();
    }
    lend.holding++;
    final held = Future.sync(work);
    final ended = held.then<void>((_) {}, onError: (Object _) {});
    final holds = _held.putIfAbsent(lend.id, () => {})..add(ended);
    unawaited(
      ended.whenComplete(() {
        lend.holding--;
        holds.remove(ended);
        if (holds.isEmpty && identical(_held[lend.id], holds)) {
          _held.remove(lend.id);
        }
      }),
    );
    return held;
  }

  /// Prepares the saved file of [source], a file of a text edition, after
  /// the preparations before it (see [prepare]).
  void _prepareLater(SourceFile source) {
    final prepare = this.prepare;
    if (prepare == null) return;
    _preparing = _preparing.then((_) async {
      if (_disposed) return;
      try {
        // The read ends once the preparation started, so other reads wait
        // only for its lookup.
        final started = await readLocalFile(
          source,
          (original) async =>
              (held: original.hold(() => prepare(original, source))),
        );
        await started?.held;
      } catch (_) {
        // The reader prepares the file when it opens it.
      }
    });
  }

  /// Whether a bound text edition holds source [id].
  /// The source ids of the bound text editions.
  Set<String> _textSources() => {
    for (final edition in _editions.values)
      if (edition.kind == EditionKind.text) ...?_editionSources[edition.id],
  };

  /// Finds the verified saved file of [source] in the catalog that is current
  /// when the lookup ends. A bind during the lookup that keeps the source
  /// under the same account leads to a new lookup in the new catalog.
  @override
  Future<Uri?> localFile(SourceFile source) async {
    var (:generation, :account) = await _settled;
    final id = _id(source);
    while (true) {
      final found = await _lookup(id, generation);
      if (found != null) return found.file?.uri;
      if (!_stillBound(account, id)) return null;
      (:generation, account: _) = await _settled;
    }
  }

  /// Looks up the verified saved file of source [id] in catalog
  /// [generation], with the digest that it matched. The result holds null
  /// when the source is not bound, or its file is missing or corrupt. A null
  /// result means that a bind replaced the catalog during the lookup. This
  /// never waits for a newer binding, so a command that a new binding waits
  /// for can call it.
  Future<({VerifiedFile? file})?> _lookup(String id, int generation) async {
    if (_disposed || _session == null) return (file: null);
    if (generation != _generation) return null;
    await _binding;
    if (_disposed) return (file: null);
    if (generation != _generation) return null;
    final record = _records[id];
    if (record == null || !record.complete) return (file: null);
    final confirmed = await _confirm(record, generation);
    if (_disposed) return (file: null);
    if (generation != _generation) return null;
    return (
      file: confirmed
          ? VerifiedFile(record.file('complete').uri, record.digest!)
          : null,
    );
  }

  /// Whether the current catalog still binds source [id] for [account].
  bool _stillBound(String? account, String id) =>
      !_disposed &&
      account != null &&
      _session?.scope.key == account &&
      _sources.containsKey(id);

  /// Verify a complete record, and reject it when its saved file no longer
  /// matches.
  Future<bool> _confirm(_Record record, int generation) async {
    final verified = await _verified(record);
    if (_disposed || generation != _generation) return false;
    if (verified && _present(record)) return true;
    await _rejectComplete(record);
    await _persist(record);
    _emit();
    return false;
  }

  /// Look at every record's storage again, which notices files changed
  /// outside the app. The app calls this when it resumes. Listeners hear
  /// only about changes that the looks found.
  @override
  Future<void> refresh() async {
    final (:generation, account: _) = await _settled;
    await _binding;
    var changed = false;
    for (final record in _records.values.toList()) {
      if (_disposed || generation != _generation) return;
      if (record.complete) {
        // A rejected record notifies listeners itself.
        await _confirm(record, generation);
      } else {
        changed |= await _observe(record);
      }
    }
    if (changed && generation == _generation) _emit();
  }

  void _networkChanged() {
    if (!_remoteAllowed) {
      ++_networkGeneration;
      _client?.close(force: true);
    }
    _emit();
    _schedule();
  }

  void _schedule() {
    if (_worker != null ||
        !_ready ||
        _disposed ||
        !_remoteAllowed ||
        _queued.isEmpty) {
      return;
    }
    _worker = _work().whenComplete(() {
      _worker = null;
      _schedule();
    });
  }

  Future<void> _work() async {
    final generation = _generation;
    while (!_disposed &&
        generation == _generation &&
        _remoteAllowed &&
        _queued.isNotEmpty) {
      final id = _queued.first;
      final record = _records[id]!;
      _active = id;
      final stopped = Completer<void>();
      _activeStopped = stopped;
      final networkGeneration = _networkGeneration;
      final session = _session!;
      final client = HttpClient()
        ..autoUncompress = false
        ..connectionTimeout = const Duration(seconds: 15);
      _client = client;
      void guard() {
        if (_disposed ||
            generation != _generation ||
            networkGeneration != _networkGeneration ||
            !_remoteAllowed ||
            !_queued.contains(id)) {
          throw const _Stopped();
        }
      }

      try {
        await _download(client, session, record, guard);
        guard();
        _queued.remove(id);
        record.requested = false;
        record.error = null;
        record.complete = true;
        await _persist(record);
        if (record.complete && _textSources().contains(id)) {
          _prepareLater(record.source);
        }
      } catch (error) {
        if (!_disposed &&
            generation == _generation &&
            _queued.contains(id) &&
            networkGeneration == _networkGeneration &&
            _remoteAllowed &&
            error is! _Stopped) {
          record.error = error is _MediaError
              ? error.message
              : error is FileSystemException
              ? 'Storage could not be written. Free storage, then retry.'
              : 'The download was interrupted. Retry to continue safely.';
          record.requested = false;
          _queued.remove(id);
          await _persist(record);
        }
      } finally {
        client.close(force: true);
        if (identical(_client, client)) {
          _client = null;
          _active = null;
          _activeStopped = null;
        }
        stopped.complete();
        _emit();
      }
    }
  }

  Future<HttpClientResponse> _get(
    HttpClient client,
    JellyfinSession session,
    List<String> path,
    void Function() guard, {
    Map<String, String> query = const {},
    Map<String, String> headers = const {},
  }) async {
    guard();
    final uri = session.scope.server.replace(
      pathSegments: [
        ...session.scope.server.pathSegments.where((part) => part.isNotEmpty),
        ...path,
      ],
      queryParameters: query.isEmpty ? null : query,
    );
    final request = await client
        .getUrl(uri)
        .timeout(const Duration(seconds: 20));
    guard();
    request.followRedirects = false;
    request.headers.set(
      'Authorization',
      'MediaBrowser Token="${session.token}"',
    );
    request.headers.set('X-Emby-Token', session.token);
    request.headers.set('Accept-Encoding', 'identity');
    headers.forEach(request.headers.set);
    final response = await request.close().timeout(const Duration(seconds: 20));
    guard();
    if (response.statusCode == 401) session.rejectCredential();
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const _MediaError(
        'Jellyfin denied this download. Check account access and sign in again.',
      );
    }
    if (response.statusCode != 200 && response.statusCode != 206) {
      throw const _MediaError(
        'Jellyfin could not provide this download. Check access, then retry.',
      );
    }
    return response;
  }

  Future<Map<String, dynamic>> _json(
    HttpClient client,
    JellyfinSession session,
    List<String> path,
    void Function() guard, {
    Map<String, String> query = const {},
  }) async {
    final response = await _get(client, session, path, guard, query: query);
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 20))) {
      guard();
      if (bytes.length + chunk.length > 4 * 1024 * 1024) {
        throw const _MediaError('Jellyfin returned invalid download details.');
      }
      bytes.addAll(chunk);
    }
    guard();
    return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  }

  Future<void> _download(
    HttpClient client,
    JellyfinSession session,
    _Record record,
    void Function() guard,
  ) async {
    final server = await _json(client, session, [
      'System',
      'Info',
      'Public',
    ], guard);
    final user = await _json(client, session, ['Users', 'Me'], guard);
    if (server['Id'] != session.scope.serverId ||
        user['Id'] != session.scope.userId ||
        (user['Policy'] as Map?)?['EnableContentDownloading'] != true) {
      throw const _MediaError('This account does not allow content downloads.');
    }
    final source = record.source;
    await _checkSource(client, session, source, guard);
    var offset = await _partialLength(record);
    if (offset > 0 &&
        (record.etag == null ||
            record.length == null ||
            offset >= record.length!)) {
      await _discardPartial(record);
      offset = 0;
    }
    final expected = source.sizeBytes ?? record.length;
    if (await freeBytes() <
        (expected == null ? 1024 * 1024 : expected - offset) + 65536) {
      throw const _MediaError(
        'Not enough free storage. Remove downloads or free storage, then retry.',
      );
    }
    guard();
    final response = await _get(
      client,
      session,
      ['Items', source.itemId, 'Download'],
      guard,
      headers: offset > 0
          ? {'Range': 'bytes=$offset-', 'If-Range': record.etag!}
          : {},
    );
    final encoding = response.headers.value('Content-Encoding');
    if (encoding != null && encoding.toLowerCase() != 'identity') {
      throw const _MediaError(
        'Jellyfin returned encoded media that cannot be verified.',
      );
    }
    final rawEtag = response.headers.value('ETag');
    final etag = rawEtag != null && RegExp(r'^"[^"\r\n]+"$').hasMatch(rawEtag)
        ? rawEtag
        : null;
    int length;
    if (response.statusCode == 206) {
      final range = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$')
          .firstMatch(response.headers.value('Content-Range') ?? '');
      final valid =
          offset > 0 &&
          range != null &&
          int.parse(range[1]!) == offset &&
          int.parse(range[2]!) + 1 == int.parse(range[3]!) &&
          int.parse(range[3]!) == record.length &&
          response.contentLength == record.length! - offset &&
          etag != null &&
          etag == record.etag;
      if (!valid) {
        await _discardPartial(record);
        throw const _MediaError(
          'The server changed this file or returned an invalid byte range. Retry from the start.',
        );
      }
      length = record.length!;
    } else {
      offset = 0;
      length = response.contentLength;
    }
    if (length <= 0 ||
        (source.sizeBytes != null && source.sizeBytes != length)) {
      await _discardPartial(record);
      throw const _MediaError(
        'The file length does not match the catalog. Refresh the library and retry.',
      );
    }
    if (await freeBytes() < length - offset + 65536) {
      throw const _MediaError(
        'Not enough free storage. Free storage, then retry.',
      );
    }
    // Remove the previous representation before publishing the new validator.
    // An interruption can then leave an empty prefix, never old bytes with a
    // new identity that a subsequent range response could incorrectly extend.
    if (offset == 0) await _discardPartial(record);
    record.length = length;
    record.etag = etag;
    record.bytes = offset;
    record.digest = null;
    record.complete = false;
    await _save(record);
    guard();
    final partial = record.file('partial');
    final type = await FileSystemEntity.type(partial.path, followLinks: false);
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.file) {
      throw const _MediaError('Download storage contains an unexpected file.');
    }
    final output = await partial.open(
      mode: offset == 0 ? FileMode.write : FileMode.append,
    );
    // Free storage is read before the first write and then once per 4 MiB.
    // Each read must cover every byte written until the next read, plus the
    // 64 KiB reserve, so a transfer fails before it can fill the storage.
    var checkedThrough = record.bytes;
    // Progress notifies listeners when the first bytes arrive, when the last
    // bytes arrive, and between them only after both 250 ms and 1 % of the
    // file passed since the previous progress notification.
    DateTime? notifiedAt;
    var notifiedBytes = record.bytes;
    try {
      await for (final chunk in response.timeout(const Duration(seconds: 20))) {
        guard();
        if (record.bytes + chunk.length > length) {
          throw const _MediaError(
            'The downloaded file is longer than expected.',
          );
        }
        if (record.bytes + chunk.length > checkedThrough) {
          final next = max(chunk.length, min(4 << 20, length - record.bytes));
          if (await freeBytes() < next + 65536) {
            throw const _MediaError(
              'Storage filled during download. Free storage, then retry.',
            );
          }
          checkedThrough = record.bytes + next;
        }
        guard();
        await output.writeFrom(chunk);
        record.bytes += chunk.length;
        final now = clock();
        if (notifiedAt == null ||
            record.bytes == length ||
            (record.bytes - notifiedBytes >= length / 100 &&
                // A clock moved backward also counts as time passed.
                now.difference(notifiedAt).abs() >=
                    const Duration(milliseconds: 250))) {
          notifiedAt = now;
          notifiedBytes = record.bytes;
          if (!_disposed) updateWatches();
        }
      }
    } finally {
      try {
        await output.flush();
      } finally {
        await output.close();
      }
    }
    guard();
    if (record.bytes != length || await partial.length() != length) {
      throw const _MediaError(
        'The download ended early. Retry to continue safely.',
      );
    }
    final digest = await _digest(partial.path, length);
    await _checkSource(client, session, source, guard);
    guard();
    final complete = record.file('complete');
    final completeType = await FileSystemEntity.type(
      complete.path,
      followLinks: false,
    );
    if (completeType != FileSystemEntityType.notFound &&
        completeType != FileSystemEntityType.file) {
      throw const _MediaError('Download storage contains an unexpected file.');
    }
    await partial.rename(complete.path);
    record.wroteComplete(length);
    final fingerprint = await _fingerprint(complete);
    guard();
    assert(record.bytes == record.length && _records[record.id] == record);
    record.digest = digest;
    record.verified = fingerprint;
  }

  Future<void> _checkSource(
    HttpClient client,
    JellyfinSession session,
    SourceFile source,
    void Function() guard,
  ) async {
    final item = await _json(
      client,
      session,
      ['Items', source.itemId],
      guard,
      query: {'userId': session.scope.userId},
    );
    if (item['Id'] != source.itemId || item['CanDownload'] != true) {
      throw const _MediaError('Jellyfin does not allow downloading this item.');
    }
    final freshBooks = buildBooks([CatalogEntry.fromJson(item, libraryId: '')]);
    final freshFiles = freshBooks
        .expand((book) => book.editions)
        .expand((edition) => edition.files);
    if (!source.isItemOriginal ||
        !freshFiles.any(
          (file) => file.key == source.key && file.isItemOriginal,
        )) {
      throw const _MediaError(
        'This source cannot use Jellyfin’s original-file download. Choose the item original.',
      );
    }
    if (source.revision.isEmpty ||
        !freshFiles.any(
          (file) => file.key == source.key && file.revision == source.revision,
        )) {
      throw const _MediaError(
        'The source changed or has no version. Refresh the library before downloading.',
      );
    }
  }

  Future<void> _discardPartial(_Record record) async {
    if (await _regularFile(record.file('partial'))) {
      await record.file('partial').delete();
    }
    record.bytes = 0;
    record.etag = null;
    record.length = null;
  }

  Future<void> _save(_Record record) {
    final data = jsonEncode({
      'key': record.source.key,
      'revision': record.source.revision,
      'length': record.length,
      'etag': record.etag,
      'digest': record.digest,
      'verified': record.verified,
      'requested': record.requested,
      'complete': record.complete,
      'error': record.error,
    });
    final blank = record.blank;
    final write = _writes.then((_) async {
      // A missing manifest restores as a blank record, so a blank record
      // without a directory needs no write.
      if (blank &&
          await FileSystemEntity.type(
                record.directory.path,
                followLinks: false,
              ) ==
              FileSystemEntityType.notFound) {
        return;
      }
      for (final directory in [
        root,
        _accountDirectory(record.accountKey),
        record.directory,
      ]) {
        await _safeDirectory(directory);
      }
      if (!await _containedDirectory(record.directory, record.accountKey)) {
        throw const _MediaError('Download storage is not a private directory.');
      }
      for (final name in ['record.next', 'record.json']) {
        final type = await FileSystemEntity.type(
          record.file(name).path,
          followLinks: false,
        );
        if (type != FileSystemEntityType.notFound &&
            type != FileSystemEntityType.file) {
          throw const _MediaError(
            'Download storage contains an unexpected file.',
          );
        }
      }
      await record.file('record.next').writeAsString(data, flush: true);
      await record.file('record.next').rename(record.file('record.json').path);
    });
    _writes = write.catchError((Object _) {});
    return write;
  }

  Future<void> _persist(_Record record) async {
    try {
      await _save(record);
    } catch (_) {
      record.error =
          'The download record could not be saved. Free storage, then retry.';
      record.complete = false;
      record.requested = false;
      if (identical(_records[record.id], record)) _queued.remove(record.id);
      _emit();
    }
  }

  @override
  Future<void> get idle async {
    await _planned;
    await _binding;
    while (true) {
      while (_operations.isNotEmpty) {
        await Future.wait(_operations.toList());
      }
      while (_worker != null) {
        await _worker;
      }
      await _writes;
      final preparing = _preparing;
      await preparing;
      if (identical(preparing, _preparing) &&
          _operations.isEmpty &&
          _worker == null) {
        return;
      }
    }
  }

  Future<void> _command(Future<void> Function() action) {
    final settled = _settled;
    final operation = _commands.then((_) async {
      final (:generation, account: _) = await settled;
      if (_disposed || generation != _generation) return;
      await _binding;
      if (_disposed || generation != _generation) return;
      await action();
    });
    _commands = operation.catchError((Object _) {});
    _operations.add(operation);
    return operation.whenComplete(() => _operations.remove(operation));
  }

  /// Invariants:
  /// - Signed-out downloads hold no records.
  /// - Each record identifies a current source revision of the account.
  /// - A complete record has a digest and a verified length.
  /// - The queue holds exactly the requested, incomplete, error-free records.
  /// - The cached source ids of each bound edition match its files.
  /// - Each record's last look at its complete file matches storage. A file
  ///   changed outside the app breaks this until [refresh] looks again.
  @override
  void checkInvariants() {
    if (_session == null && (_records.isNotEmpty || _queued.isNotEmpty)) {
      throw StateError('Signed-out downloads must expose no account records.');
    }
    final editionSources = {
      for (final edition in _editions.values)
        edition.id: [for (final source in edition.files) _id(source)],
    };
    if (jsonEncode(editionSources) != jsonEncode(_editionSources) ||
        !editionSources.values.every(
          (ids) => ids.every(_sources.containsKey),
        )) {
      throw StateError('Cached edition sources must match the bound catalog.');
    }
    if (_held.values.any((held) => held.isEmpty)) {
      throw StateError('A source without held work must have no entry.');
    }
    for (final record in _records.values) {
      if (record.savedLength != _savedLength(record)) {
        throw StateError('Download status must match the saved complete file.');
      }
      if (record.accountKey != _session?.scope.key ||
          !_sources.containsKey(record.id) ||
          _id(record.source) != record.id) {
        throw StateError(
          'Every download must identify a current account source revision.',
        );
      }
      if (record.complete &&
          (record.digest == null ||
              record.length == null ||
              record.length! <= 0 ||
              record.bytes != record.length)) {
        throw StateError(
          'Complete downloads need a digest and a verified length.',
        );
      }
      if (_queued.contains(record.id) !=
          (record.requested && !record.complete && record.error == null)) {
        throw StateError('The queue must agree with durable file requests.');
      }
    }
  }

  /// Notifies a change other than byte progress to every listener, and
  /// reads the leftover files again once something shows them.
  void _emit() {
    if (_disposed) return;
    notifyListeners();
    if (_leftovers != null) unawaited(reloadLeftovers());
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _session?.credentialChanges.removeListener(_networkChanged);
    policy.removeListener(_networkChanged);
    _client?.close(force: true);
    _leftovers?.dispose();
    super.dispose();
  }
}

typedef _Catalog = ({int generation, String? account});

class _Record {
  _Record(this.id, this.source, this.directory, this.accountKey);
  final String id;
  final SourceFile source;
  final Directory directory;
  final String accountKey;
  int bytes = 0;
  int? length;
  String? etag;
  String? error;

  /// The SHA-256 digest that the saved file must match. A new digest forgets
  /// [verified], which belongs to the file that matched the old one.
  String? get digest => _digest;
  set digest(String? value) {
    _digest = value;
    verified = null;
  }

  String? _digest;

  /// The fingerprint of the saved file when its bytes last matched [digest],
  /// or null when no file matched it yet.
  String? verified;
  bool complete = false;
  bool requested = false;

  /// The length of the regular complete file at the last look at or write to
  /// this directory, or null when there was none.
  int? savedLength;

  /// The regular derived-file bytes at the last look.
  int derivedBytes = 0;

  /// Counts looks and writes, so an older look cannot replace newer facts.
  int diskVersion = 0;

  File file(String name) => File('${directory.path}/$name');

  /// Whether the manifest would hold only what a missing manifest restores.
  bool get blank =>
      length == null &&
      etag == null &&
      digest == null &&
      error == null &&
      !requested &&
      !complete;

  void wroteComplete(int length) {
    diskVersion++;
    savedLength = length;
  }
}

/// One read of a source's saved file ([LocalDownloads.readLocalFile]), and
/// the work that it holds.
class _Lend {
  _Lend(this.id, this.generation, this.removals);

  /// The source id, the catalog generation and the count of the source's
  /// removals when the read began.
  final String id;
  final int generation;
  final int removals;

  /// Whether the read runs.
  bool reading = true;

  /// How many pieces of held work run.
  int holding = 0;
}

class _MediaError implements Exception {
  const _MediaError(this.message);
  final String message;
}

class _Stopped implements Exception {
  const _Stopped();
}
