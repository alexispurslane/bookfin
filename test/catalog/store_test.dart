import 'dart:convert';

import 'package:bookfin/catalog/jellyfin.dart';
import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/catalog/store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'controller_test.dart' show account;
import 'model_test.dart' show entry;

class MemorySecureStorage extends FlutterSecureStorage {
  final values = <String, String>{};
  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values[key];
  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    values.remove(key);
  }
}

void main() {
  test(
    'offline catalog serialization retains relationships without credentials',
    () {
      final scope = account('alice').scope;
      final cache = CatalogCache(
        scope: scope,
        libraries: [const BookLibrary('books', 'Books')],
        selected: {'books'},
        entries: [
          entry('one'),
          entry('ebook', type: 'Book'),
        ],
        completedAt: DateTime.utc(2026, 11, 1),
        edits: CatalogEdits(
          bookLinks: {'ebook:source': 'book:one'},
          details: {
            'book:one': const BookDetails(
              title: 'Saved title',
              author: 'Writer',
              series: 'Garden',
              seriesOrder: 1.5,
            ),
          },
        ),
      );
      final encoded = cache.encode();
      expect(encoded, isNot(contains('token-alice')));
      final reopened = CatalogCache.decode(scope, encoded);
      final book = buildBooks(reopened.entries, edits: reopened.edits).single;
      expect(book.title, 'Saved title');
      expect(book.editions, hasLength(2));
      expect(reopened.completedAt, DateTime.utc(2026, 11, 1));
    },
  );

  test('another account cannot decode the same cached catalog', () {
    final cache = CatalogCache(
      scope: account('alice').scope,
      entries: [entry('private')],
      selected: {'books'},
    );
    expect(
      () => CatalogCache.decode(account('bob').scope, cache.encode()),
      throwsFormatException,
    );
  });

  test('cached entries outside the saved selected libraries are rejected', () {
    final scope = account('alice').scope;
    final encoded = jsonEncode({
      'version': 1,
      'scope': scope.toJson(),
      'libraries': [],
      'selected': [],
      'entries': [entry('one').toJson()],
      'edits': CatalogEdits().toJson(),
    });
    expect(() => CatalogCache.decode(scope, encoded), throwsFormatException);
  });

  test(
    'secure session persistence restores the token and sign-out deletes it',
    () async {
      final storage = MemorySecureStorage();
      final vault = SecureCredentialStore(storage: storage);
      await vault.write(account('alice'));
      final restored = await SecureCredentialStore(storage: storage).read();
      expect(restored!.token, 'token-alice');
      await vault.write(null);
      expect(await vault.read(), isNull);
      expect(
        storage.values.values.any((value) => value.contains('token-alice')),
        isFalse,
      );
    },
  );

  test(
    'one device identity is retained through secure session replacement',
    () async {
      final storage = MemorySecureStorage();
      final vault = SecureCredentialStore(storage: storage);
      final first = await vault.deviceId();
      await vault.write(account('alice'));
      await vault.write(null);
      expect(await SecureCredentialStore(storage: storage).deviceId(), first);
      expect(first.length, greaterThanOrEqualTo(22));
    },
  );
}
