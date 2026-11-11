import 'crossings.dart';
import 'outlines_stub.dart' if (dart.library.io) 'outlines_io.dart' as platform;

/// The store where [Crossings] keeps text outlines between launches. It
/// finds its folder in the background, so the first frame never waits for
/// it. Where the platform keeps no files, it keeps nothing.
OutlineStore createOutlineStore() => _Found(platform.findOutlineStore());

/// The outline store that [found] gives, once it gives one, or no store.
class _Found implements OutlineStore {
  _Found(this.found);
  final Future<OutlineStore?> found;

  @override
  Future<String?> read(String key) async => (await found)?.read(key);

  @override
  Future<void> write(String key, String value) async =>
      (await found)?.write(key, value);
}
