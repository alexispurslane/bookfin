import 'catalog_files_stub.dart'
    if (dart.library.io) 'catalog_files_io.dart'
    as platform;

/// Usable account discoveries plus the first I/O failure, if any. A failed
/// file or interrupted scan must not discard accounts already discovered.
typedef CatalogDiscovery = ({
  Set<String> keys,
  ({Exception error, StackTrace stack})? failure,
});

/// Application-private catalog and choice text files. Implementations map
/// opaque storage keys to safe filenames and preserve read errors.
/// One LocalCatalogStore owns operations on these files for the app lifetime.
abstract interface class CatalogFiles {
  /// Returns null only if no committed file exists, never for unreadable data.
  Future<String?> read(String key);

  /// Atomically replaces the committed text, flushing the replacement first.
  /// A failed write leaves the previous committed file intact.
  Future<void> write(String key, String text);

  /// Removes this key's committed text and incomplete replacement, if any.
  /// Retained unreadable originals remain available for recovery.
  Future<void> remove(String key);

  /// Retains the exact committed bytes under a separate, content-addressed
  /// name. Failure must prevent replacement of the damaged original.
  Future<void> preserve(String key);

  /// Discovers account keys in committed snapshots for background migration.
  /// [identify] is a pure decoder, run with disk work off the UI isolate, so
  /// file storage need not know catalog formats or move whole catalogs back.
  /// Unidentifiable data stays untouched for recovery by its account owner.
  Future<CatalogDiscovery> catalogKeys(String? Function(String text) identify);
}

/// Native platforms keep files beside the host's private media directory.
/// The browser retains its existing preference storage instead.
CatalogFiles? createCatalogFiles() => platform.createCatalogFiles();
