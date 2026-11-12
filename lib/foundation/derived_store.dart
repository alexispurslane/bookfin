import 'derived_store_stub.dart'
    if (dart.library.io) 'derived_store_io.dart'
    as platform;

/// Where a data source keeps derived values between launches: values that
/// it can derive again, such as the text outlines of Crossings and the heard
/// windows of HeardWindows. A lost or unreadable value costs only the work
/// to derive it again, so a store never holds a personal record.
abstract class DerivedStore {
  /// The kept value of [key], or null when none is kept.
  Future<String?> read(String key);

  /// Keeps [value] for [key], replacing any older value. A crash during the
  /// write leaves the old value or the new one, never a broken one.
  Future<void> write(String key, String value);
}

/// The store of the folder [name] beside the app's media storage, as the
/// covers keep theirs. It finds the folder in the background, so the first
/// frame never waits for it. Where the platform keeps no files, it keeps
/// nothing.
DerivedStore createDerivedStore(String name) =>
    _Found(platform.findDerivedStore(name));

/// The store that [found] gives, once it gives one, or no store.
class _Found implements DerivedStore {
  _Found(this.found);
  final Future<DerivedStore?> found;

  @override
  Future<String?> read(String key) async => (await found)?.read(key);

  @override
  Future<void> write(String key, String value) async =>
      (await found)?.write(key, value);
}
