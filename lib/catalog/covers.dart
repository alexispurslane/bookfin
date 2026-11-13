import 'dart:typed_data';

import 'jellyfin.dart';
import 'model.dart';
import 'covers_stub.dart' if (dart.library.io) 'covers_io.dart' as platform;

/// Book covers from Jellyfin, with a copy of each kept on the phone.
abstract class Covers {
  /// The cover image bytes, or null when the item has no cover image or
  /// Jellyfin cannot be reached and no copy is kept.
  Future<Uint8List?> load(JellyfinSession session, CoverRef cover);

  /// A file of the cover blurred the way the player chip blurs it, for the
  /// system media player. Null when [load] gives no readable cover image.
  Future<Uri?> blurred(JellyfinSession session, CoverRef cover);

  /// Removes only [account]'s kept covers, including blurred copies. Waits
  /// for older loads to stop writing so they cannot recreate cleared files.
  /// Loads return no image through [afterRemoval], which finishes the owning
  /// clear and retires the visible catalog before this protection ends.
  /// Failures propagate.
  Future<void> clear(
    AccountScope account, {
    Future<void> Function()? afterRemoval,
  });
}

/// Null where the platform keeps no covers. Screens then draw generated covers.
Future<Covers?> createCovers() => platform.createCovers();

/// The Jellyfin primary image of a cover, scaled by the server for a phone.
Uri coverUri(JellyfinSession session, CoverRef cover) {
  final server = session.scope.server;
  return server.replace(
    pathSegments: [
      ...server.pathSegments.where((segment) => segment.isNotEmpty),
      'Items',
      cover.itemId,
      'Images',
      'Primary',
    ],
    queryParameters: {'tag': cover.tag, 'fillHeight': '720', 'quality': '90'},
  );
}
