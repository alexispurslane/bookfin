import 'package:flutter/foundation.dart';

import '../catalog/jellyfin.dart';
import '../catalog/model.dart';

enum MediaNetwork { unknown, disconnected, wifi, mobile }

enum MediaLocation { local, remote, blocked }

class MediaPolicy extends ChangeNotifier {
  MediaNetwork _network = MediaNetwork.unknown;
  bool _mobileAllowed = false;
  MediaNetwork get network => _network;
  set network(MediaNetwork value) {
    if (_network == value) return;
    _network = value;
    notifyListeners();
  }

  bool get mobileAllowed => _mobileAllowed;
  void allowMobileForSession() {
    _mobileAllowed = true;
    notifyListeners();
  }

  void resetSession() {
    _mobileAllowed = false;
    notifyListeners();
  }

  MediaLocation choose({required bool verifiedLocal}) {
    if (verifiedLocal) return MediaLocation.local;
    return _network == MediaNetwork.wifi ||
            _network == MediaNetwork.mobile && _mobileAllowed
        ? MediaLocation.remote
        : MediaLocation.blocked;
  }
}

enum DownloadPhase { none, partial, downloading, waiting, failed, downloaded }

class EditionDownload {
  const EditionDownload({
    this.phase = DownloadPhase.none,
    this.completeFiles = 0,
    this.totalFiles = 0,
    this.bytes = 0,
    this.unavailableBytes = 0,
    this.totalBytes,
    this.message,
  });
  final DownloadPhase phase;
  final int completeFiles;
  final int totalFiles;
  final int bytes;

  /// Saved original and derived-file bytes unavailable for local use.
  final int unavailableBytes;
  final int? totalBytes;
  final String? message;
  String get label => switch (phase) {
    DownloadPhase.none => 'Not downloaded',
    DownloadPhase.partial => 'Partial',
    DownloadPhase.downloading => 'Downloading',
    DownloadPhase.waiting => 'Waiting for Wi-Fi',
    DownloadPhase.failed => 'Download failed',
    DownloadPhase.downloaded => 'Downloaded',
  };

  /// The changes that a person can ask of the download in this state, the
  /// most useful first. Every screen offers these and no others.
  ///
  /// A transfer that runs or waits can only be canceled. Otherwise a download
  /// that failed or saved some bytes is retried, and one that saved nothing
  /// is requested. Anything on the phone, and a failure, can be removed.
  List<DownloadAction> get actions {
    if (phase == DownloadPhase.downloading || phase == DownloadPhase.waiting) {
      return const [DownloadAction.cancel];
    }
    final failed = phase == DownloadPhase.failed;
    return [
      if (phase != DownloadPhase.downloaded)
        failed || bytes > 0 ? DownloadAction.retry : DownloadAction.request,
      if (phase == DownloadPhase.downloaded ||
          failed ||
          bytes > 0 ||
          unavailableBytes > 0 ||
          completeFiles > 0)
        DownloadAction.remove,
    ];
  }
}

/// A change to an edition's download. [request] and [retry] both ask for the
/// files; retry continues a download that failed or stopped part way.
enum DownloadAction { request, retry, cancel, remove }

class RetainedDownload {
  const RetainedDownload({
    required this.accountKey,
    required this.binding,
    required this.id,
    required this.sourceKey,
    required this.revision,
    required this.bytes,
  });
  final String accountKey;
  final Object binding;
  final String id;
  final String? sourceKey;
  final String? revision;
  final int bytes;
  bool get removable => sourceKey != null && revision != null;
}

abstract class Downloads extends ChangeNotifier {
  Downloads(this.policy);
  final MediaPolicy policy;
  bool get supported;
  Future<void> bind(JellyfinSession? session, List<Book> books);
  EditionDownload status(Edition edition);
  Future<void> request(Edition edition);
  Future<void> cancel(Edition edition);
  Future<void> remove(Edition edition);
  Future<List<RetainedDownload>> retainedStorage() async => const [];
  Future<void> removeRetained(RetainedDownload download) async =>
      throw UnsupportedError('Retained storage is unavailable.');
  Future<Uri?> localFile(SourceFile source);

  /// Keep a verified original and its derived files owned until loading ends.
  /// A null result means the source is no longer locally available.
  Future<T?> readLocalFile<T>(
    SourceFile source,
    Future<T> Function(Uri original) read, {
    void Function(bool Function() live)? onOwnership,
  }) async {
    final uri = await localFile(source);
    onOwnership?.call(() => true);
    return uri == null ? null : read(uri);
  }

  Future<void> get idle;
  Future<void> refresh() async {}
  void checkInvariants();
}
