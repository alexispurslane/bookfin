import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'jellyfin.dart';
import 'model.dart';

abstract interface class CredentialStore {
  Future<JellyfinSession?> read();
  Future<void> write(JellyfinSession? session);
  Future<String> deviceId();
}

/// Keeps the saved catalog text of each account. The catalog encodes and
/// decodes the text, off the UI isolate, so the store only moves text.
abstract interface class CatalogStore {
  /// The saved catalog text of [scope], or null when none is saved.
  Future<String?> read(AccountScope scope);

  /// Replaces the saved catalog text of [scope] with [text].
  Future<void> write(AccountScope scope, String text);
}

/// The saved catalog of one account: its Jellyfin book [libraries], the ids
/// of the ones that the user [hidden], and the [entries] of the others.
///
/// A library shows unless the user hid it, so a library that Jellyfin adds
/// later shows by default. Each entry belongs to a shown library.
class CatalogCache {
  CatalogCache({
    required this.scope,
    List<BookLibrary> libraries = const [],
    Set<String> hidden = const {},
    List<CatalogEntry> entries = const [],
    CatalogEdits? edits,
    this.completedAt,
    this.accessBlocked = false,
    this.content,
  }) : libraries = List.unmodifiable(libraries),
       hidden = Set.unmodifiable(hidden),
       entries = List.unmodifiable(entries),
       edits = edits ?? CatalogEdits();
  final AccountScope scope;
  final List<BookLibrary> libraries;
  final Set<String> hidden;
  final List<CatalogEntry> entries;
  final CatalogEdits edits;

  /// The successful refresh recorded in this saved snapshot. The controller
  /// can complete later unchanged refreshes without rewriting this snapshot.
  final DateTime? completedAt;
  final bool accessBlocked;

  /// The ids of the [libraries] that show: every library that the user did
  /// not hide.
  Set<String> get shown => {
    for (final library in libraries)
      if (!hidden.contains(library.id)) library.id,
  };

  /// A digest of [entries] and [edits], which decide the books, or null when
  /// it is not known. Two caches with the same content have the same books.
  final String? content;

  /// This cache with its [content] digest. It encodes every entry, so it is
  /// whole-catalog work for another isolate.
  CatalogCache withContent() => CatalogCache(
    scope: scope,
    libraries: libraries,
    hidden: hidden,
    entries: entries,
    edits: edits,
    completedAt: completedAt,
    accessBlocked: accessBlocked,
    content: sha256
        .convert(
          utf8.encode(
            jsonEncode([
              for (final entry in entries) entry.toJson(),
              edits.toJson(),
            ]),
          ),
        )
        .toString(),
  );

  String encode() => jsonEncode({
    'version': 2,
    'accessBlocked': accessBlocked,
    'scope': scope.toJson(),
    'libraries': libraries.map((library) => library.toJson()).toList(),
    'hidden': hidden.toList(),
    'entries': entries.map((entry) => entry.toJson()).toList(),
    'edits': edits.toJson(),
    'completedAt': completedAt?.toIso8601String(),
    'content': content,
  });

  /// The cache that [value] encodes. Throws a [FormatException] when the
  /// text is not a catalog of [scope]. The catalog builds the books from the
  /// result in the same isolate hop, and a failed build also counts as an
  /// unreadable catalog there.
  ///
  /// Version 1 saved the libraries that the user selected, under a rule
  /// where a library showed only when selected. Those choices did not hide
  /// anything, so a version 1 catalog decodes with no hidden library, and
  /// keeps its entries and corrections.
  static CatalogCache decode(AccountScope scope, String value) {
    try {
      final json = jsonDecode(value) as Map<String, dynamic>;
      final version = json['version'];
      if ((version != 1 && version != 2) ||
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
      final result = CatalogCache(
        scope: scope,
        accessBlocked: json['accessBlocked'] as bool? ?? false,
        libraries: [
          for (final library
              in (json['libraries'] as List).cast<Map<String, dynamic>>())
            BookLibrary(library['id'] as String, library['name'] as String),
        ],
        hidden: version == 1 ? const {} : Set.from(json['hidden'] as List),
        entries: entries,
        edits: CatalogEdits.fromJson(json['edits'] as Map<String, dynamic>),
        completedAt: json['completedAt'] == null
            ? null
            : DateTime.parse(json['completedAt'] as String),
        content: json['content'] as String?,
      );
      final shown = result.shown;
      if (entries.any((entry) => !shown.contains(entry.libraryId)) ||
          entries.map((entry) => entry.id).toSet().length != entries.length) {
        throw const FormatException();
      }
      return result;
    } catch (_) {
      throw const FormatException(
        'Saved catalog is invalid or belongs to another account.',
      );
    }
  }
}

class LocalCatalogStore implements CatalogStore {
  late final _preferences = SharedPreferencesAsync();
  @override
  Future<String?> read(AccountScope scope) =>
      _preferences.getString(_key(scope));

  @override
  Future<void> write(AccountScope scope, String text) =>
      _preferences.setString(_key(scope), text);

  String _key(AccountScope scope) =>
      'bookfin.catalog.v1.${base64Url.encode(utf8.encode(scope.key))}';
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
