import 'package:flutter/foundation.dart';

import '../catalog/jellyfin.dart';
import '../catalog/model.dart';

/// A saved file of a download that Downloads verified: where it is, and the
/// SHA-256 digest of its bytes, as lowercase hexadecimal. Downloads computed
/// the digest when the download completed, and its file still matched it at
/// the time of the read.
class VerifiedFile {
  const VerifiedFile(this.uri, this.digest) : _hold = null;

  /// The file that a read of [Downloads.readLocalFile] lends, whose
  /// [hold] calls [hold].
  const VerifiedFile.lent(
    this.uri,
    this.digest, {
    required Future<void> Function(
      Future<void> Function() work,
      Future<void> Function()? beforeRemoval,
    )
    this._hold,
  });

  final Uri uri;
  final String digest;
  final Future<void> Function(
    Future<void> Function() work,
    Future<void> Function()? beforeRemoval,
  )?
  _hold;

  /// Runs [work], such as a write of a file derived from this download,
  /// while Downloads keeps the download: a removal of the download waits
  /// until [work] ends, and other reads do not wait. Gives the end of
  /// [work], with its error.
  ///
  /// A read of [Downloads.readLocalFile] can hold its file while the read
  /// runs, and later while work that it held runs. A hold after that is a
  /// bug, and throws a [StateError]. Once a removal of the download began,
  /// [work] does not run. A file that Downloads did not lend, as a test
  /// makes, has no download to keep, so [work] runs at once.
  /// With [beforeRemoval], removal first asks the consumer to finish using
  /// the file. It runs outside Downloads' command queue, so the consumer can
  /// open another book while releasing this one. A failure refuses removal.
  /// The consumer must still end [work] after releasing the file.
  Future<void> hold(
    Future<void> Function() work, {
    Future<void> Function()? beforeRemoval,
  }) => _hold == null ? work() : _hold(work, beforeRemoval);
}

/// A requested removal could not safely finish. The caller may retry it.
class DownloadRemovalException implements Exception {
  const DownloadRemovalException(this.message);
  final String message;
  @override
  String toString() => message;
}

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
    this.removing = false,
  });
  final DownloadPhase phase;
  final int completeFiles;
  final int totalFiles;
  final int bytes;

  /// Saved original and derived-file bytes unavailable for local use.
  final int unavailableBytes;
  final int? totalBytes;
  final String? message;

  /// Files remain usable by their current owner until it releases them.
  final bool removing;
  String get label => removing
      ? 'Removal pending'
      : switch (phase) {
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
    if (removing) return const [];
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

  @override
  bool operator ==(Object other) =>
      other is EditionDownload &&
      other.phase == phase &&
      other.completeFiles == completeFiles &&
      other.totalFiles == totalFiles &&
      other.bytes == bytes &&
      other.unavailableBytes == unavailableBytes &&
      other.totalBytes == totalBytes &&
      other.removing == removing &&
      other.message == message;

  @override
  int get hashCode => Object.hash(
    phase,
    completeFiles,
    totalFiles,
    bytes,
    unavailableBytes,
    totalBytes,
    message,
    removing,
  );
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

/// What Downloads last learned about the saved files of the bound account
/// that no bound edition owns.
class LeftoverFiles {
  const LeftoverFiles({
    this.entries = const [],
    this.reading = false,
    this.error,
  });

  /// The leftovers of the last read that succeeded, sorted by id.
  final List<RetainedDownload> entries;

  /// Whether the first read for the bound account runs, so no list is known.
  final bool reading;

  /// Why the last read failed, or null when it succeeded.
  final Object? error;
}

abstract class Downloads extends ChangeNotifier {
  Downloads(this.policy);
  final MediaPolicy policy;
  bool get supported;
  Future<void> bind(JellyfinSession? session, List<Book> books);
  EditionDownload status(Edition edition);

  /// The watched editions by id, each with the status that it last showed.
  final Map<String, ({Edition edition, ValueNotifier<EditionDownload> state})>
  _watches = {};

  /// [status] of [edition], which notifies only when that status changes.
  /// Byte progress of the edition notifies it, and notifies nothing else.
  /// Changes of other editions do not. Each call for one edition id returns
  /// the same listenable.
  ValueListenable<EditionDownload> watch(Edition edition) {
    final state = _watches[edition.id]?.state ?? ValueNotifier(status(edition));
    _watches[edition.id] = (edition: edition, state: state);
    return state;
  }

  /// Gives each watched edition its current [status]. A watch notifies only
  /// when its status changed. [notifyListeners] calls this first, so a
  /// subclass that only notifies broadly keeps every watch true. A subclass
  /// calls this alone for byte progress, so only the watches of the
  /// editions that gained bytes notify.
  @protected
  void updateWatches() {
    for (final watch in _watches.values.toList()) {
      watch.state.value = status(watch.edition);
    }
  }

  @override
  void notifyListeners() {
    updateWatches();
    super.notifyListeners();
  }

  Future<void> request(Edition edition);
  Future<void> cancel(Edition edition);

  /// Removes local files only after their consumers safely release them.
  /// Playing audio continues until pause or book switch. The future completes
  /// after removal, or fails if a required save or the removal fails. Repeated
  /// requests for the same pending removal share its result.
  Future<void> remove(Edition edition);

  /// Removes the confirmed account's current and retained downloads through
  /// the normal removal boundary. Waits for file users and active transfers;
  /// completes only after removal. A changed account/source or failed removal
  /// throws. [beforeRemoval] rechecks required record saves/uploads after
  /// file users finish, before each removal. A failure preserves those files.
  /// It must not request another download read. Other accounts are untouched.
  /// [afterRemoval] finishes the owning operation while requests remain
  /// blocked. Platforms without storage still run that continuation.
  Future<void> clearAccount(
    JellyfinSession confirmed, {
    Future<void> Function()? beforeRemoval,
    Future<void> Function()? afterRemoval,
  }) async {
    if (supported) throw UnsupportedError('Account removal is unavailable.');
    await afterRemoval?.call();
  }

  /// Notifies when a download starts, finishes, fails, stops or waits, or
  /// when saved files change. This object notifies its own listeners at the
  /// same times. Byte progress notifies only [watch].
  Listenable get phases => this;
  Future<List<RetainedDownload>> retainedStorage() async => const [];

  /// The leftover files of the bound account. The first use starts a read.
  /// After that, Downloads reads them again when [phases] notifies and when
  /// [reloadLeftovers] runs, and notifies once when each read ends.
  ValueListenable<LeftoverFiles> get leftovers => _noLeftovers;
  late final _noLeftovers = ValueNotifier(const LeftoverFiles());

  /// Reads the leftover files again. The future ends when [leftovers] holds
  /// the result. A read that fails sets [LeftoverFiles.error] and keeps the
  /// last list.
  Future<void> reloadLeftovers() async {}
  Future<void> removeRetained(RetainedDownload download) async =>
      throw UnsupportedError('Retained storage is unavailable.');
  Future<Uri?> localFile(SourceFile source);

  /// Keep a verified original and its derived files owned until loading ends,
  /// and then until the work that [read] holds ([VerifiedFile.hold]) ends.
  /// [read] receives the saved file and the digest that it matches. A null
  /// result means the source is no longer locally available.
  Future<T?> readLocalFile<T>(
    SourceFile source,
    Future<T> Function(VerifiedFile original) read, {
    void Function(bool Function() live)? onOwnership,
  });

  Future<void> get idle;
  Future<void> refresh() async {}
  void checkInvariants();

  @override
  void dispose() {
    for (final watch in _watches.values) {
      watch.state.dispose();
    }
    _noLeftovers.dispose();
    super.dispose();
  }
}
