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
    this.totalBytes,
    this.message,
  });
  final DownloadPhase phase;
  final int completeFiles;
  final int totalFiles;
  final int bytes;
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
}

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
  Future<void> get idle;
  Future<void> refresh() async {}
  void checkInvariants();
}
