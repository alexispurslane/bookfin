import 'crossings.dart';
import 'outlines_stub.dart' if (dart.library.io) 'outlines_io.dart' as platform;

/// The store where [Crossings] keeps text outlines between launches, or
/// null where the platform keeps no files.
Future<OutlineStore?> createOutlineStore() => platform.createOutlineStore();
