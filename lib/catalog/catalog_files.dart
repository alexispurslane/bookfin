import 'catalog_files_stub.dart'
    if (dart.library.io) 'catalog_files_io.dart'
    as platform;

/// Application-private catalog text files. Keys are opaque account identities;
/// implementations must map them to safe filenames and preserve read errors.
/// One LocalCatalogStore owns operations on these files for the app lifetime.
abstract interface class CatalogFiles {
  /// Returns null only if no committed file exists, never for unreadable data.
  Future<String?> read(String key);

  /// Atomically replaces the committed text, flushing the replacement first.
  /// A failed write leaves the previous committed file intact.
  Future<void> write(String key, String text);
}

/// Native platforms keep files beside the host's private media directory.
/// The browser retains its existing preference storage instead.
CatalogFiles? createCatalogFiles() => platform.createCatalogFiles();
