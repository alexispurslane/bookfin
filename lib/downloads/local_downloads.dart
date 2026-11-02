import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../catalog/jellyfin.dart';
import '../catalog/model.dart';
import 'downloads.dart';

class LocalDownloads extends Downloads {
  LocalDownloads({
    required this.root,
    required this.freeBytes,
    required MediaPolicy policy,
  }) : super(policy) {
    policy.addListener(_networkChanged);
  }

  final Directory root;
  final Future<int> Function() freeBytes;
  JellyfinSession? _session;
  Map<String, SourceFile> _sources = {};
  Map<String, Edition> _editions = {};
  final Map<String, _Record> _records = {};
  final Set<String> _queued = {};
  Future<void>? _binding;
  Future<void>? _worker;
  Future<void> _writes = Future.value();
  Future<void> _commands = Future.value();
  final Set<Future<void>> _operations = {};
  HttpClient? _client;
  String? _active;
  String? _signature;
  int _generation = 0;
  int _networkGeneration = 0;
  bool _ready = false;
  bool _disposed = false;
  String? _storageError;

  @override
  bool get supported => true;

  static String _hash(String value) =>
      sha256.convert(utf8.encode(value)).toString();
  static String _id(SourceFile source) =>
      _hash(jsonEncode([source.key, source.revision]));
  bool get _remoteAllowed =>
      policy.choose(verifiedLocal: false) == MediaLocation.remote;

  @override
  Future<void> bind(JellyfinSession? session, List<Book> books) {
    final editions = {
      for (final book in books)
        for (final edition in book.editions) edition.id: edition,
    };
    final sources = {
      for (final edition in editions.values)
        for (final source in edition.files) _id(source): source,
    };
    final signature = jsonEncode([
      session?.scope.key,
      session?.token,
      for (final entry in sources.entries) [entry.key, entry.value.sizeBytes],
    ]);
    _editions = editions;
    if (_signature == signature) return _binding ?? Future.value();
    final accountChanged =
        _session?.scope.key != session?.scope.key ||
        _session?.token != session?.token;
    _signature = signature;
    _ready = false;
    final generation = ++_generation;
    _client?.close(force: true);
    _session = session;
    _sources = sources;
    _queued.clear();
    _records.clear();
    _storageError = null;
    if (accountChanged) policy.resetSession();
    _emit();
    return _binding = _restore(generation, session);
  }

  Future<void> _restore(int generation, JellyfinSession? session) async {
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
          final record = _Record(entry.key, entry.value, directory);
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
          if (record.complete && !await _verified(record)) {
            record.complete = false;
          }
          record.bytes = record.complete
              ? record.length!
              : await _partialLength(record);
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

  Future<bool> _regularFile(File file) async =>
      await FileSystemEntity.type(file.path, followLinks: false) ==
      FileSystemEntityType.file;

  bool _present(_Record record) {
    try {
      return record.complete &&
          record.length != null &&
          record.length! > 0 &&
          FileSystemEntity.typeSync(
                record.file('complete').path,
                followLinks: false,
              ) ==
              FileSystemEntityType.file &&
          record.file('complete').lengthSync() == record.length &&
          (record.source.sizeBytes == null ||
              record.source.sizeBytes == record.length);
    } catch (_) {
      return false;
    }
  }

  Future<bool> _verified(_Record record) async {
    if (!_present(record) || record.digest == null) return false;
    try {
      return (await sha256.bind(record.file('complete').openRead()).first)
              .toString() ==
          record.digest;
    } catch (_) {
      return false;
    }
  }

  Future<int> _partialLength(_Record record) async =>
      await _regularFile(record.file('partial'))
      ? await record.file('partial').length()
      : 0;

  @override
  EditionDownload status(Edition edition) {
    if (_session == null || !_editions.containsKey(edition.id)) {
      return const EditionDownload();
    }
    var complete = 0;
    var bytes = 0;
    String? error = _storageError;
    var queued = false;
    for (final source in edition.files) {
      final record = _records[_id(source)];
      if (record == null) continue;
      final present = _present(record);
      if (present) complete++;
      bytes += present
          ? record.length!
          : record.complete
          ? 0
          : record.bytes;
      error ??= record.error;
      queued |= _queued.contains(record.id);
    }
    final all = edition.files.isNotEmpty && complete == edition.files.length;
    final phase = all
        ? DownloadPhase.downloaded
        : error != null
        ? DownloadPhase.failed
        : queued
        ? (_remoteAllowed ? DownloadPhase.downloading : DownloadPhase.waiting)
        : complete > 0
        ? DownloadPhase.partial
        : DownloadPhase.none;
    return EditionDownload(
      phase: phase,
      completeFiles: complete,
      totalFiles: edition.files.length,
      bytes: bytes,
      totalBytes: edition.files.every((source) => source.sizeBytes != null)
          ? edition.files.fold(0, (total, source) => total! + source.sizeBytes!)
          : null,
      message: error,
    );
  }

  Edition _current(Edition edition) {
    final current = _editions[edition.id];
    if (_disposed ||
        _session == null ||
        current == null ||
        jsonEncode(current.files.map(_id).toList()) !=
            jsonEncode(edition.files.map(_id).toList())) {
      throw StateError('This edition is not in the active account catalog.');
    }
    return current;
  }

  @override
  Future<void> request(Edition edition) => _command(() => _request(edition));

  Future<void> _request(Edition edition) async {
    final generation = _generation;
    await _binding;
    if (_disposed || generation != _generation) return;
    _current(edition);
    if (_storageError != null) {
      _emit();
      return;
    }
    for (final source in edition.files) {
      final record = _records[_id(source)]!;
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
    _current(edition);
    final records = [
      for (final source in edition.files)
        if (_records[_id(source)] != null) _records[_id(source)]!,
    ];
    for (final record in records) {
      _queued.remove(record.id);
      record.requested = false;
      record.error = null;
      if (_active == record.id) _client?.close(force: true);
    }
    _emit();
    await _worker;
    for (final record in records) {
      await _persist(record);
    }
  }

  @override
  Future<void> remove(Edition edition) => _command(() => _remove(edition));

  Future<void> _remove(Edition edition) async {
    _current(edition);
    final generation = _generation;
    final records = [
      for (final source in edition.files)
        if (_records[_id(source)] != null) _records[_id(source)]!,
    ];
    await _cancel(edition);
    try {
      for (final record in records) {
        record.complete = false;
        record.bytes = 0;
        for (final directory in await _savedVersions(record)) {
          for (final name in [
            'partial',
            'complete',
            'record.json',
            'record.next',
          ]) {
            final file = File('${directory.path}/$name');
            if (await _regularFile(file)) await file.delete();
          }
        }
        record.length = null;
        record.etag = null;
        record.digest = null;
      }
    } finally {
      if (generation == _generation) _emit();
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
      final manifest = File('${entity.path}/record.json');
      if (!await _regularFile(manifest) || await manifest.length() > 65536) {
        continue;
      }
      try {
        final data =
            jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;
        final revision = data['revision'];
        final name = entity.uri.pathSegments
            .where((part) => part.isNotEmpty)
            .last;
        if (data['key'] == record.source.key &&
            revision is String &&
            name == _hash(jsonEncode([record.source.key, revision]))) {
          directories.add(entity);
        }
      } catch (_) {}
    }
    return directories;
  }

  @override
  Future<Uri?> localFile(SourceFile source) async {
    if (_session == null || _disposed) return null;
    final generation = _generation;
    await _binding;
    if (_disposed || generation != _generation) return null;
    final record = _records[_id(source)];
    if (record == null || !record.complete) return null;
    final verified = await _verified(record);
    if (_disposed || generation != _generation) return null;
    if (verified && _present(record)) return record.file('complete').uri;
    record.complete = false;
    record.bytes = 0;
    await _persist(record);
    _emit();
    return null;
  }

  @override
  Future<void> refresh() async {
    await _binding;
    for (final source in _sources.values.toList()) {
      await localFile(source);
    }
    _emit();
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
        }
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
    try {
      await for (final chunk in response.timeout(const Duration(seconds: 20))) {
        guard();
        if (record.bytes + chunk.length > length) {
          throw const _MediaError(
            'The downloaded file is longer than expected.',
          );
        }
        if (await freeBytes() < chunk.length + 65536) {
          throw const _MediaError(
            'Storage filled during download. Free storage, then retry.',
          );
        }
        guard();
        await output.writeFrom(chunk);
        record.bytes += chunk.length;
        _emit();
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
    final sources = (item['MediaSources'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();
    if (sources.isEmpty ||
        sources.first['Id'] != source.mediaSourceId ||
        sources.first['IsRemote'] == true ||
        (sources.first['Type'] != null && sources.first['Type'] != 'Default')) {
      throw const _MediaError(
        'This source cannot use Jellyfin’s original-file download. Choose the default source.',
      );
    }
    final freshBooks = buildBooks([CatalogEntry.fromJson(item, libraryId: '')]);
    final freshFiles = freshBooks
        .expand((book) => book.editions)
        .expand((edition) => edition.files);
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
      if (!_disposed && generation == _generation) {
        await action();
      }
    });
    _commands = operation.catchError((Object _) {});
    _operations.add(operation);
    return operation.whenComplete(() => _operations.remove(operation));
  }

  @override
  void checkInvariants() {
    if (_session == null && (_records.isNotEmpty || _queued.isNotEmpty)) {
      throw StateError('Signed-out downloads must expose no account records.');
    }
    for (final record in _records.values) {
      if (!_sources.containsKey(record.id) || _id(record.source) != record.id) {
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

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    policy.removeListener(_networkChanged);
    _client?.close(force: true);
    super.dispose();
  }
}

class _Record {
  _Record(this.id, this.source, this.directory);
  final String id;
  final SourceFile source;
  final Directory directory;
  int bytes = 0;
  int? length;
  String? etag;
  String? digest;
  String? error;
  bool complete = false;
  bool requested = false;
  File file(String name) => File('${directory.path}/$name');
}

class _MediaError implements Exception {
  const _MediaError(this.message);
  final String message;
}

class _Stopped implements Exception {
  const _Stopped();
}
