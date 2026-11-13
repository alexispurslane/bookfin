import '../catalog/controller.dart';
import '../catalog/covers.dart';
import '../catalog/jellyfin.dart';
import '../downloads/downloads.dart';
import '../sync/coordinator.dart';

/// The Settings controller's confirmed operation. Each existing data owner
/// removes only its own account data. The catalog retires refreshes until all
/// file removal has finished. Records, login and appearance remain intact.
/// The initial required save/upload must succeed before any removal. Records
/// made while files are held are checked again at removal. Any failure stops
/// further removal and propagates, so the screen cannot report completion.
Future<void> clearAccountData({
  required JellyfinSession confirmed,
  required CatalogController catalog,
  required RecordSync sync,
  required Downloads downloads,
  required Covers? covers,
}) => catalog.clearSavedLibrary(
  confirmed,
  beforeClear: (guard) async {
    if (downloads.supported && covers == null) {
      throw Exception(
        'Cover storage is unavailable. Restart Bookfin and retry Clear data.',
      );
    }
    Future<void> preserveRecords() async {
      guard();
      try {
        await sync.requireUploaded(confirmed);
      } on Exception {
        throw Exception(
          'Your records could not be saved or uploaded. Check device storage and your Jellyfin connection, sign in again if needed, then retry Clear data.',
        );
      }
      guard();
    }

    await preserveRecords();
    await downloads.clearAccount(confirmed, beforeRemoval: preserveRecords);
    guard();
    await covers?.clear(confirmed.scope);
    guard();
  },
);
