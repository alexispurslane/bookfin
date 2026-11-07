import 'dart:async';
import 'dart:convert';
import 'dart:io';
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
  }) : super(policy) {
    policy.addListener(_networkChanged);
  }

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
  Future<void>? _worker;
  Future<void> _writes = Future.value();
  Future<void> _commands = Future.value();
  final Set<Future<void>> _operations = {};
  final Map<String, Object> _reading = {};
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
  final ChangeNotifier _phases = ChangeNotifier();

  @override
  bool get supported => true;
  @override
  Listenable get phases => _phases;

  static String _hash(String value) =>
      sha256.convert(utf8.encode(value)).toString();
  static String _id(SourceFile source) =>
      _hash(jsonEncode([source.key, source.revision]));
  static final _idPattern = RegExp(r'^[a-f0-9]{64}$');
  bool get _remoteAllowed =>
      policy.choose(verifiedLocal: false) == MediaLocation.remote;

  @override
  Future<void> bind(JellyfinSession? session, List<Book> books) {
    final editions = {
      for (final book in books)
        for (final edition in book.editions) edition.id: edition,
    };
    final editionSources = {
      for (final edition in editions.values)
        edition.id: [for (final source in edition.files) _id(source)],
    };
    final sources = {
      for (final edition in editions.values)
        for (final (index, source) in edition.files.indexed)
          editionSources[edition.id]![index]: source,
    };
    final signature = jsonEncode([
      session?.scope.key,
      session?.token,
      for (final entry in sources.entries)
        [entry.key, entry.value.sizeBytes, entry.value.isItemOriginal],
    ]);
    _editions = editions;
    _editionSources = editionSources;
    if (_signature == signature) return _binding ?? Future.value();
    final accountChanged =
        _session?.scope.key != session?.scope.key ||
        _session?.token != session?.token;
    _signature = signature;
    _retainedBinding = Object();
    _ready = false;
    final generation = ++_generation;
    _client?.close(force: true);
    _session = session;
    _sources = sources;
    _queued.clear();
    _records.clear();
    _storageError = null;
    final binding = _binding = _restore(generation, session, _commands);
    if (accountChanged) policy.resetSession();
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
        await _safeDirectory(root);
        final account = Directory('${root.path}/${_hash(session.scope.key)}');
        await _safeDirectory(account);
        for (final entry in _sources.entries.toList()) {
          if (_disposed || generation != _generation) return;
          final directory = Directory('${account.path}/${entry.key}');
          await _safeDirectory(directory);
          final record = _Record(
            entry.key,
            entry.value,
            directory,
            session.scope.key,
          );
          final manifest = record.file('record.json');
          if (await _regularFile(manifest)) {
            try {
              final data = jsonDecode(
                await manifest.readAsString(),
              ) as Map<String, dynamic>;
              if (data['key'] == record.source.key &&
                  data['revision'] == record.source.revision) {
                record.length = data['length'] as int?;
                record.etag = data['etag'] as String?;
                record.digest = data['digest'] as String?;
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
          _records[entry.key] = record;
          if (record.requested && !record.complete && record.error == null) {
            _queued.add(entry.key);
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

  Future<bool> _containedDirectory(
    Directory directory,
    String accountKey,
  ) async {
    final account = _accountDirectory(accountKey);
    final name = directory.uri.pathSegments
        .where((part) => part.isNotEmpty)
        .last;
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

  Future<bool> _verified(_Record record) async {
    await _observe(record);
    if (!_present(record) || record.digest == null) return false;
    try {
      return (await sha256.bind(record.file('complete').openRead()).first)
              .toString() ==
          record.digest;
    } catch (_) {
      return false;
    }
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
      final record = _records[id]!;
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
    if (_reading.isNotEmpty) {
      try {
        _current(edition).forEach(_reading.remove);
      } on StateError {
        return _command(() => _remove(edition));
      }
    }
    return _command(() => _remove(edition));
  }

  Future<void> _remove(Edition edition) async {
    final ids = _current(edition);
    final generation = _generation;
    final records = [for (final id in ids) ?_records[id]];
    await _cancel(edition);
    void guard() {
      if (_disposed || generation != _generation) {
        throw StateError('The active download catalog changed.');
      }
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

  Future<List<Directory>> _savedVersions(_Record record) async {
    final directories = [record.directory];
    await for (final entity in record.directory.parent.list(
      followLinks: false,
    )) {
      if (entity is! Directory || entity.path == record.directory.path) {
        continue;
      }
      final identity = await _savedIdentity(entity, _session!.scope.key);
      if (identity?.key == record.source.key) directories.add(entity);
    }
    return directories;
  }

  Future<({String key, String revision})?> _savedIdentity(
    Directory directory,
    String accountKey,
  ) async {
    if (!await _containedDirectory(directory, accountKey)) return null;
    final id = directory.uri.pathSegments.where((part) => part.isNotEmpty).last;
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
    final id = directory.uri.pathSegments.where((part) => part.isNotEmpty).last;
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
    final generation = _generation;
    await _binding;
    final session = _session;
    if (_disposed || generation != _generation || session == null) {
      return const [];
    }
    final account = _accountDirectory(session.scope.key);
    if ([root, account].any(
      (directory) =>
          FileSystemEntity.typeSync(directory.path, followLinks: false) !=
          FileSystemEntityType.directory,
    )) {
      throw StateError('Cannot read private download storage.');
    }
    final retained = <RetainedDownload>[];
    await for (final entity in account.list(followLinks: false)) {
      if (_disposed || generation != _generation) return const [];
      if (entity is! Directory) continue;
      final saved = await _storedDownload(entity, session, _retainedBinding);
      if (saved != null && saved.bytes > 0 && !_sources.containsKey(saved.id)) {
        retained.add(saved);
      }
    }
    if (_disposed || generation != _generation) return const [];
    retained.sort((first, second) => first.id.compareTo(second.id));
    return List.unmodifiable(retained);
  }

  @override
  Future<void> removeRetained(RetainedDownload download) => _command(() async {
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
    try {
      await _deleteOwnedFiles(directory, guard);
    } finally {
      if (generation == _generation) _emit();
    }
  });

  Future<void> _deleteOwnedFiles(
    Directory directory,
    void Function() guard,
  ) async {
    guard();
    if (_session == null ||
        !await _containedDirectory(directory, _session!.scope.key)) {
      throw StateError('Download storage is no longer a private directory.');
    }
    await DerivedBookFiles.remove(directory);
    for (final name in ['partial', 'complete', 'record.next', 'record.json']) {
      guard();
      if (_session == null ||
          !await _containedDirectory(directory, _session!.scope.key)) {
        throw StateError('Download storage is no longer a private directory.');
      }
      final file = File('${directory.path}/$name');
      if (await _regularFile(file)) {
        guard();
        await file.delete();
      }
    }
  }

  @override
  Future<T?> readLocalFile<T>(
    SourceFile source,
    Future<T> Function(Uri original) read, {
    void Function(bool Function() live)? onOwnership,
  }) async {
    T? result;
    // The existing command owner also orders removal and account restoration.
    // A converter must settle before either can reclaim its source directory.
    await _command(() async {
      final uri = await localFile(source);
      if (uri == null) return;
      final generation = _generation;
      final token = Object();
      final id = _id(source);
      _reading[id] = token;
      onOwnership?.call(
        () =>
            !_disposed &&
            generation == _generation &&
            identical(_reading[id], token),
      );
      try {
        result = await read(uri);
      } finally {
        if (identical(_reading[id], token)) _reading.remove(id);
      }
    });
    return result;
  }

  @override
  Future<Uri?> localFile(SourceFile source) async {
    if (_session == null || _disposed) return null;
    final generation = _generation;
    await _binding;
    if (_disposed || generation != _generation) return null;
    final record = _records[_id(source)];
    if (record == null || !record.complete) return null;
    return await _confirm(record, generation)
        ? record.file('complete').uri
        : null;
  }

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
    final generation = _generation;
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
          if (!_disposed) notifyListeners();
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
    final digest = (await sha256.bind(partial.openRead()).first).toString();
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
    guard();
    assert(record.bytes == record.length && _records[record.id] == record);
    record.digest = digest;
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
      'requested': record.requested,
      'complete': record.complete,
      'error': record.error,
    });
    final write = _writes.then((_) async {
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
    await _binding;
    while (_operations.isNotEmpty) {
      await Future.wait(_operations.toList());
    }
    while (_worker != null) {
      await _worker;
    }
    await _writes;
  }

  Future<void> _command(Future<void> Function() action) {
    final generation = _generation;
    final operation = _commands.then((_) async {
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

  /// Notifies a change other than byte progress to both kinds of listeners.
  void _emit() {
    if (_disposed) return;
    notifyListeners();
    _phases.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    policy.removeListener(_networkChanged);
    _client?.close(force: true);
    _phases.dispose();
    super.dispose();
  }
}

class _Record {
  _Record(this.id, this.source, this.directory, this.accountKey);
  final String id;
  final SourceFile source;
  final Directory directory;
  final String accountKey;
  int bytes = 0;
  int? length;
  String? etag;
  String? digest;
  String? error;
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

  void wroteComplete(int length) {
    diskVersion++;
    savedLength = length;
  }
}

class _MediaError implements Exception {
  const _MediaError(this.message);
  final String message;
}

class _Stopped implements Exception {
  const _Stopped();
}
