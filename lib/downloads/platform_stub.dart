import '../catalog/jellyfin.dart';
import '../catalog/model.dart';
import 'downloads.dart';

Future<Downloads> createDownloads(MediaPolicy policy) async =>
    UnavailableDownloads(policy);

class UnavailableDownloads extends Downloads {
  UnavailableDownloads(super.policy);
  @override
  bool get supported => false;
  @override
  Future<void> bind(JellyfinSession? session, List<Book> books) async {}
  @override
  EditionDownload status(Edition edition) => const EditionDownload();
  @override
  Future<void> request(Edition edition) async {}
  @override
  Future<void> cancel(Edition edition) async {}
  @override
  Future<void> remove(Edition edition) async {}
  @override
  Future<Uri?> localFile(SourceFile source) async => null;
  @override
  Future<T?> readLocalFile<T>(
    SourceFile source,
    Future<T> Function(VerifiedFile original) read, {
    void Function(bool Function() live)? onOwnership,
  }) async => null;
  @override
  Future<void> get idle async {}
  @override
  void checkInvariants() {}
}
