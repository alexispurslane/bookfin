import 'package:bookfin/catalog/jellyfin.dart';
import 'package:bookfin/sync/transport.dart';

/// Replaces only the network exchange in coordinator policy tests. Writer
/// registration and storage remain the real store's responsibility.
class ControlledTransport extends RecordTransport {
  ControlledTransport(super.records, this.exchange);
  final Future<SyncReport> Function(JellyfinSession, JellyfinClient) exchange;

  @override
  Future<SyncReport> synchronize(
    JellyfinSession session,
    JellyfinClient client,
  ) => exchange(session, client);
}
