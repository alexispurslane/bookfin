import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'catalog_files.dart';
import 'jellyfin.dart';
import 'model.dart';

abstract interface class CredentialStore {
  Future<JellyfinSession?> read();
  Future<void> write(JellyfinSession? session);
  Future<String> deviceId();
}

/// Keeps disposable server text and durable choices independently per account.
/// The store owns migration and ordering; the controller owns visible adoption.
abstract interface class CatalogStore {
  /// The saved catalog text of [scope], or null when none is saved.
  Future<String?> read(AccountScope scope);

  /// Replaces the saved catalog text of [scope] with [text].
  Future<void> write(AccountScope scope, String text);

  /// Removes only the server snapshot of [scope]. User choices and retained
  /// unreadable originals survive; a failed removal throws.
  Future<void> clearCache(AccountScope scope);

  /// Loads durable choices, extracting legacy choices before a cache can
  /// replace them. A retained-data notice must be shown to the person.
  Future<CatalogChoices> readChoices(AccountScope scope);

  /// Commits only the small choice record. The cache is never rewritten.
  Future<void> writeChoices(AccountScope scope, CatalogChoices choices);
}

/// Durable account choices. [retainedUnreadable] records that older data is
/// kept separately for recovery; it is never silently presented as no choices.
class CatalogChoices {
  CatalogChoices({
    CatalogEdits? edits,
    Set<String> hidden = const {},
    this.retainedUnreadable = false,
  }) : edits = edits ?? CatalogEdits(),
       hidden = Set.unmodifiable(hidden);

  final CatalogEdits edits;
  final Set<String> hidden;
  final bool retainedUnreadable;

  String? get notice => retainedUnreadable
      ? 'Some saved catalog choices could not be read. The damaged data was kept for recovery.'
      : null;

  CatalogChoices change({CatalogEdits? edits, Set<String>? hidden}) =>
      CatalogChoices(
        edits: edits ?? this.edits,
        hidden: hidden ?? this.hidden,
        retainedUnreadable: retainedUnreadable,
      );

  String encode(AccountScope scope) => jsonEncode({
    'version': 1,
    'scope': scope.toJson(),
    'edits': edits.toJson(),
    'hidden': hidden.toList(),
    'retainedUnreadable': retainedUnreadable,
  });

  static CatalogChoices decode(AccountScope scope, String text) {
    final json = jsonDecode(text) as Map<String, dynamic>;
    if (json['version'] != 1 ||
        AccountScope.fromJson(json['scope'] as Map<String, dynamic>).key !=
            scope.key ||
        json.keys.any(
          (key) => !const {
            'version',
            'scope',
            'edits',
            'hidden',
            'retainedUnreadable',
          }.contains(key),
        )) {
      throw const FormatException('Saved catalog choices are not supported.');
    }
    return CatalogChoices(
      edits: _readEdits(json['edits'], complete: true),
      hidden: Set<String>.from(json['hidden'] as List),
      retainedUnreadable: json['retainedUnreadable'] as bool,
    );
  }

  static CatalogEdits _readEdits(Object? value, {bool complete = false}) {
    final json = value as Map<String, dynamic>;
    const fields = {'books', 'recordings', 'details', 'orders'};
    if ((complete && fields.any((field) => json[field] is! Map)) ||
        json.keys.any((key) => !fields.contains(key))) {
      throw const FormatException(
        'Saved catalog corrections are not supported.',
      );
    }
    final details = json['details'] as Map<String, dynamic>? ?? {};
    for (final value in details.values) {
      final detail = value as Map<String, dynamic>;
      if (detail.keys.any(
        (key) => !const {'title', 'author', 'series', 'order'}.contains(key),
      )) {
        throw const FormatException('Saved book details are not supported.');
      }
    }
    return CatalogEdits.fromJson(json);
  }
}

String _encodeChoices(({AccountScope scope, CatalogChoices choices}) input) =>
    input.choices.encode(input.scope);
CatalogChoices _decodeChoices(({AccountScope scope, String text}) input) {
  try {
    return CatalogChoices.decode(input.scope, input.text);
  } on Exception {
    throw const FormatException('Saved catalog choices could not be decoded.');
  } on TypeError {
    throw const FormatException('Saved catalog choices could not be decoded.');
  }
}

/// Disposable server data. User choices are supplied separately when building
/// the visible library. Version 3 contains no authoritative user choices.
class CatalogCache {
  CatalogCache({
    required this.scope,
    List<BookLibrary> libraries = const [],
    List<CatalogEntry> entries = const [],
    Set<String>? included,
    this.completedAt,
    this.accessBlocked = false,
    this.content,
  }) : libraries = List.unmodifiable(libraries),
       entries = List.unmodifiable(entries),
       included = Set.unmodifiable(
         included ?? libraries.map((library) => library.id).toSet(),
       );
  final AccountScope scope;
  final List<BookLibrary> libraries;
  final List<CatalogEntry> entries;

  /// Libraries whose complete entries this snapshot holds, including empty ones.
  final Set<String> included;
  final DateTime? completedAt;
  final bool accessBlocked;

  /// Digest of server entries only. Choices cannot invalidate this digest.
  final String? content;

  CatalogCache withContent() {
    return CatalogCache(
      scope: scope,
      libraries: libraries,
      entries: entries,
      included: included,
      completedAt: completedAt,
      accessBlocked: accessBlocked,
      content: sha256
          .convert(
            utf8.encode(
              jsonEncode([for (final entry in entries) entry.toJson()]),
            ),
          )
          .toString(),
    );
  }

  String encode() => jsonEncode({
    'version': 3,
    'accessBlocked': accessBlocked,
    'scope': scope.toJson(),
    'libraries': libraries.map((library) => library.toJson()).toList(),
    'entries': entries.map((entry) => entry.toJson()).toList(),
    'included': included.toList(),
    'completedAt': completedAt?.toIso8601String(),
    'content': content,
  });

  /// Accepts old server snapshots without adopting their choices. Version 1
  /// selected libraries did not mean hidden libraries. Version 2 forbade
  /// entries from hidden libraries. New snapshots may retain hidden entries.
  static CatalogCache decode(AccountScope scope, String value) {
    try {
      final json = jsonDecode(value) as Map<String, dynamic>;
      final version = json['version'];
      if ((version != 1 && version != 2 && version != 3) ||
          AccountScope.fromJson(json['scope'] as Map<String, dynamic>).key !=
              scope.key) {
        throw const FormatException();
      }
      final entries = (json['entries'] as List)
          .cast<Map<String, dynamic>>()
          .map(
            (entry) => CatalogEntry.fromJson(
              entry['item'] as Map<String, dynamic>,
              libraryId: entry['library'] as String,
            ),
          )
          .toList();
      final libraries = [
        for (final library
            in (json['libraries'] as List).cast<Map<String, dynamic>>())
          BookLibrary(library['id'] as String, library['name'] as String),
      ];
      final allowed = libraries.map((library) => library.id).toSet();
      if (version == 2) {
        allowed.removeAll(Set<String>.from(json['hidden'] as List));
      }
      if (entries.any((entry) => !allowed.contains(entry.libraryId)) ||
          entries.map((entry) => entry.id).toSet().length != entries.length) {
        throw const FormatException();
      }
      return CatalogCache(
        scope: scope,
        libraries: libraries,
        entries: entries,
        included: version == 3
            ? Set<String>.from(json['included'] as List)
            : version == 1
            ? Set<String>.from(json['selected'] as List)
            : allowed,
        accessBlocked: json['accessBlocked'] as bool? ?? false,
        completedAt: json['completedAt'] == null
            ? null
            : DateTime.parse(json['completedAt'] as String),
        // Old digests included edits and cannot be compared with server data.
        content: version == 3 ? json['content'] as String? : null,
      );
    } on Exception {
      throw const FormatException(
        'Saved catalog is invalid or belongs to another account.',
      );
    } on TypeError {
      throw const FormatException(
        'Saved catalog is invalid or belongs to another account.',
      );
    }
  }
}

/// Extracts choices even if the entries cannot be built. Cache damage still
/// requires retention. This conversion runs off the UI isolate.
({CatalogChoices? choices, bool damaged}) _legacyChoices(
  ({AccountScope scope, String text}) input,
) {
  CatalogChoices? choices;
  try {
    final json = jsonDecode(input.text) as Map<String, dynamic>;
    if (AccountScope.fromJson(json['scope'] as Map<String, dynamic>).key !=
        input.scope.key) {
      throw const FormatException();
    }
    switch (json['version']) {
      case 1:
      case 2:
        choices = CatalogChoices(
          edits: CatalogChoices._readEdits(json['edits']),
          hidden: json['version'] == 1
              ? {}
              : Set<String>.from(json['hidden'] as List),
        );
      case 3:
        break;
      default:
        throw const FormatException();
    }
    final cache = CatalogCache.decode(input.scope, input.text);
    // A structurally valid legacy entry can still fail book construction. It
    // is unreadable to the catalog too, so keep the original before replacing.
    if (choices != null) buildBooks(cache.entries, edits: choices.edits);
    return (choices: choices, damaged: false);
  } on Exception {
    return (choices: choices, damaged: true);
  } on TypeError {
    return (choices: choices, damaged: true);
  }
}

/// Identifies accounts without adopting any data discovered by the scan.
/// Every migration re-reads that account through its ordered storage owner.
String? _catalogKey(String text) {
  try {
    final json = jsonDecode(text) as Map<String, dynamic>;
    if (!json.containsKey('entries')) return null;
    final scope = AccountScope.fromJson(json['scope'] as Map<String, dynamic>);
    return 'bookfin.catalog.v1.${base64Url.encode(utf8.encode(scope.key))}';
  } on Exception {
    return null;
  } on TypeError {
    return null;
  }
}

/// Owns account storage and migration. All operations for one account run in
/// request order. Choices commit before the sole legacy representation can be
/// removed or replaced. A committed choice file always wins, including empty
/// choices after Reset corrections. The app keeps one store for its lifetime.
///
/// Invariants: each queued account has one completion future; failures release
/// the queue; a prepared account has durable choices and its old unreadable
/// sources have been retained. [checkInvariants] checks the in-memory boundary.
class LocalCatalogStore implements CatalogStore {
  factory LocalCatalogStore({CatalogFiles? files}) {
    final native = files ?? createCatalogFiles();
    return native == null
        ? LocalCatalogStore.preferences()
        : LocalCatalogStore._(native);
  }

  /// The browser fallback: separate preference records for choices and cache.
  LocalCatalogStore.preferences() : _files = null;
  LocalCatalogStore._(this._files);
  final CatalogFiles? _files;
  late final _preferences = SharedPreferencesAsync();
  final _pending = <String, Future<void>>{};
  final _prepared = <String>{};
  Future<void>? _migration;

  @override
  Future<String?> read(AccountScope scope) =>
      _ordered(_key(scope), () => _read(_key(scope)));

  @override
  Future<void> clearCache(AccountScope scope) =>
      _ordered(_key(scope), () async {
        // Legacy catalogs can still hold the only copy of user corrections.
        await _prepare(scope);
        await _preferences.remove(_key(scope));
        await _files?.remove(_key(scope));
      });

  Future<String?> _read(String key) async =>
      await _files?.read(key) ?? await _preferences.getString(key);

  Future<void> _write(String key, String text) async {
    if (_files case final files?) {
      await files.write(key, text);
    } else {
      await _preferences.setString(key, text);
    }
  }

  @override
  Future<void> write(AccountScope scope, String text) =>
      _ordered(_key(scope), () async {
        await _prepare(scope);
        await _write(_key(scope), text);
      });

  @override
  Future<CatalogChoices> readChoices(AccountScope scope) => _ordered(
    _key(scope),
    () async => await _existingChoices(scope) ?? await _prepare(scope),
  );

  @override
  Future<void> writeChoices(AccountScope scope, CatalogChoices choices) =>
      _ordered(_key(scope), () async {
        final previous = await _existingChoices(scope) ?? await _prepare(scope);
        // A correction cannot dismiss a retained-data notice.
        final saved = CatalogChoices(
          edits: choices.edits,
          hidden: choices.hidden,
          retainedUnreadable:
              previous.retainedUnreadable || choices.retainedUnreadable,
        );
        await _write(
          _choiceKey(scope),
          await compute(_encodeChoices, (scope: scope, choices: saved)),
        );
      });

  Future<void> _retain(String key, {String? preferenceText}) async {
    if (_files case final files? when preferenceText == null) {
      await files.preserve(key);
    } else {
      final text = preferenceText ?? await _preferences.getString(key);
      if (text == null) return;
      final digest = await compute(
        (String value) => sha256.convert(utf8.encode(value)).toString(),
        text,
      );
      final kept = 'bookfin.catalog.unreadable.$digest';
      // Content-addressed copies are retry-safe and do not replace earlier damage.
      await _write(kept, text);
    }
  }

  /// Reads only the small authoritative record. Unknown or corrupt choices
  /// are retained before a replacement records the unresolved recovery notice.
  Future<CatalogChoices?> _existingChoices(AccountScope scope) async {
    final key = _choiceKey(scope);
    try {
      final text = await _read(key);
      return text == null
          ? null
          : await compute(_decodeChoices, (scope: scope, text: text));
    } on FormatException {
      await _retain(key);
    }
    final choices = CatalogChoices(retainedUnreadable: true);
    await _write(
      key,
      await compute(_encodeChoices, (scope: scope, choices: choices)),
    );
    return choices;
  }

  Future<CatalogChoices> _prepare(AccountScope scope) async {
    final key = _key(scope);
    assert(_pending.containsKey(key));
    final choiceKey = _choiceKey(scope);
    final choices = await _existingChoices(scope);
    if (_prepared.contains(key) && choices != null) return choices;
    var damaged = false;

    // Inspect both sources before replacing either. Native legacy choices win
    // over preferences, but a server-only native cache has no choices to win.
    final sources = <({String? text, bool preference})>[];
    if (_files case final files?) {
      try {
        sources.add((text: await files.read(key), preference: false));
      } on FormatException {
        await files.preserve(key);
        damaged = true;
      }
    }
    sources.add((text: await _preferences.getString(key), preference: true));
    CatalogChoices? legacy;
    for (final source in sources) {
      final text = source.text;
      if (text == null) continue;
      final read = await compute(_legacyChoices, (scope: scope, text: text));
      legacy ??= read.choices;
      if (read.damaged) {
        await _retain(key, preferenceText: source.preference ? text : null);
        damaged = true;
      }
    }
    // A corrupt committed choice file is still newer than any retained legacy
    // choices. Never revive those stale choices over it.
    final known = choices ?? legacy ?? CatalogChoices();
    final result = CatalogChoices(
      edits: known.edits,
      hidden: known.hidden,
      retainedUnreadable: known.retainedUnreadable || damaged,
    );
    if (choices == null ||
        result.retainedUnreadable != choices.retainedUnreadable) {
      await _write(
        choiceKey,
        await compute(_encodeChoices, (scope: scope, choices: result)),
      );
    }
    _prepared.add(key);
    return result;
  }

  /// Migrates retained preference and native accounts, including inactive ones. Each
  /// account is attempted, and the first failure is reported. Legacy bytes are
  /// removed only after choices and their catalog or retained copy commit.
  Future<void> migrateLegacy() =>
      _migration ??= _migrateLegacy().whenComplete(() {
        _migration = null;
      });

  Future<void> _migrateLegacy() async {
    final files = _files;
    Object? failure;
    StackTrace? trace;
    Future<CatalogDiscovery> discover(
      Future<CatalogDiscovery> operation,
    ) async {
      try {
        return await operation;
      } on Exception catch (error, stack) {
        return (keys: <String>{}, failure: (error: error, stack: stack));
      }
    }

    final sources = await Future.wait([
      discover(
        _preferences.getKeys().then((keys) => (keys: keys, failure: null)),
      ),
      discover(
        files?.catalogKeys(_catalogKey) ??
            Future.value((keys: <String>{}, failure: null)),
      ),
    ]);
    for (final source in sources) {
      if (source.failure case final failed?) {
        failure ??= failed.error;
        trace ??= failed.stack;
      }
    }
    final preferenceKeys = sources[0].keys;
    final keys = {
      ...preferenceKeys.where((key) => key.startsWith('bookfin.catalog.v1.')),
      ...sources[1].keys,
    };
    for (final key in keys) {
      try {
        final scope = _scope(key);
        await _ordered(key, () async {
          await _prepare(scope);
          if (files != null) {
            if (await files.read(key) == null) {
              final text = await _preferences.getString(key);
              if (text != null) await files.write(key, text);
            }
            if (preferenceKeys.contains(key)) await _preferences.remove(key);
          }
        });
      } on Exception catch (error, stack) {
        failure ??= error;
        trace ??= stack;
      }
    }
    if (failure case final error?) Error.throwWithStackTrace(error, trace!);
  }

  /// Checks that every prepared account still has its committed choices.
  /// Runs on demand only; it never migrates or repairs data.
  Future<void> checkInvariants() async {
    for (final key in _prepared) {
      final scope = _scope(key);
      final text = await _read(_choiceKey(scope));
      if (text == null) {
        throw StateError('Prepared accounts must have committed choices.');
      }
      await compute(_decodeChoices, (scope: scope, text: text));
    }
    for (final key in _pending.keys) {
      _scope(key);
    }
  }

  AccountScope _scope(String key) {
    if (!key.startsWith('bookfin.catalog.v1.')) {
      throw const FormatException('Invalid catalog account key.');
    }
    // One short account identity costs less to parse here than an isolate hop.
    final parts = jsonDecode(
      utf8.decode(
        base64Url.decode(key.substring('bookfin.catalog.v1.'.length)),
      ),
    );
    if (parts is! List ||
        parts.length != 3 ||
        parts.any((part) => part is! String)) {
      throw const FormatException('Invalid catalog account key.');
    }
    return AccountScope(
      server: parseServer(parts[0] as String),
      serverId: parts[1] as String,
      userId: parts[2] as String,
    );
  }

  Future<T> _ordered<T>(String key, Future<T> Function() operation) async {
    final previous = _pending[key];
    final done = Completer<void>();
    _pending[key] = done.future;
    try {
      await previous;
      return await operation();
    } finally {
      done.complete();
      if (identical(_pending[key], done.future)) _pending.remove(key);
    }
  }

  String _key(AccountScope scope) =>
      'bookfin.catalog.v1.${base64Url.encode(utf8.encode(scope.key))}';
  String _choiceKey(AccountScope scope) =>
      'bookfin.catalog.choices.v1.${base64Url.encode(utf8.encode(scope.key))}';
}

class SecureCredentialStore implements CredentialStore {
  SecureCredentialStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
            // The data protection keychain needs a keychain-access-groups
            // entitlement, and so a signing team. A locally signed macOS
            // build keeps its items in the login keychain instead.
            mOptions: MacOsOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
              useDataProtectionKeyChain: false,
            ),
          );
  final FlutterSecureStorage _storage;
  JellyfinSession? _webSession;
  String? _webDevice;
  @override
  Future<JellyfinSession?> read() async {
    if (kIsWeb) return _webSession;
    final raw = await _storage.read(key: 'bookfin.session.v1');
    return raw == null
        ? null
        : JellyfinSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  @override
  Future<void> write(JellyfinSession? session) async {
    if (kIsWeb) {
      _webSession = session;
      return;
    }
    if (session == null) {
      await _storage.delete(key: 'bookfin.session.v1');
    } else {
      await _storage.write(
        key: 'bookfin.session.v1',
        value: jsonEncode(session.toJson()),
      );
    }
  }

  @override
  Future<String> deviceId() async {
    if (kIsWeb) return _webDevice ??= _newDevice();
    final saved = await _storage.read(key: 'bookfin.device.v1');
    if (saved != null && saved.isNotEmpty) return saved;
    final created = _newDevice();
    await _storage.write(key: 'bookfin.device.v1', value: created);
    return created;
  }

  String _newDevice() {
    final random = Random.secure();
    return base64Url
        .encode(List.generate(24, (_) => random.nextInt(256)))
        .replaceAll('=', '');
  }
}
