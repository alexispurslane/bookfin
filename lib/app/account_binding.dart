import 'dart:async';

import '../catalog/controller.dart';
import '../catalog/jellyfin.dart';
import '../catalog/model.dart';
import '../downloads/downloads.dart';
import '../playback/playback.dart';
import '../reader/session.dart';
import '../sync/coordinator.dart';

/// Hands the catalog's account and books to every source that works for one
/// account: Downloads, Playback, the reader and record sync. It binds them
/// when it starts, and again whenever the visible account or the book list
/// changes. Blocked library access shows as no account.
///
/// Only a new account or blocked access unbinds the sources. A refresh that
/// cannot reach the server changes neither, so the saved library, saved
/// places and history stay bound.
///
/// Invariant, checked by [checkInvariants]: the account and books last
/// handed out are the catalog's current ones, unless the binding is disposed.
class AccountBinding {
  AccountBinding({
    required this.catalog,
    this.downloads,
    this.playback,
    this.reader,
    this.sync,
  }) {
    _accountKey = catalog.session?.scope.key;
    catalog.addListener(_catalogChanged);
    _bindSources();
    _bindSync();
  }

  final CatalogController catalog;
  final Downloads? downloads;
  final Playback? playback;
  final ReaderSession? reader;
  final RecordSync? sync;

  /// The account and books last handed to Downloads, Playback and the reader.
  JellyfinSession? _boundSession;
  List<Book>? _boundBooks;

  /// The account of [_boundSession], or of the catalog when access is
  /// blocked, to tell a new account from blocked access.
  String? _accountKey;

  /// Counts bindings, so that a binding that a newer one replaced stops.
  int _generation = 0;
  bool _disposed = false;

  JellyfinSession? get _visibleSession =>
      catalog.accessBlocked ? null : catalog.session;

  void checkInvariants() {
    if (_disposed) return;
    if (!identical(_boundSession, _visibleSession) ||
        !identical(_boundBooks, catalog.books)) {
      throw StateError('The sources hold an account or books that changed.');
    }
  }

  /// Stops following the catalog. A binding in progress stops before its
  /// next source.
  void dispose() {
    _disposed = true;
    _generation++;
    catalog.removeListener(_catalogChanged);
  }

  void _catalogChanged() {
    // The catalog replaces its session and book list when either changes, so
    // identity shows whether this notice changed what the sources hold.
    if (!identical(_boundSession, _visibleSession) ||
        !identical(_boundBooks, catalog.books)) {
      final key = catalog.session?.scope.key;
      if (_accountKey != key || catalog.accessBlocked) {
        // The open book and the open publication belong to the old account,
        // so they close before the new account's binding starts.
        unawaited(playback?.bind(null, []));
        unawaited(reader?.bind(null, []));
      }
      _accountKey = key;
      _bindSources();
    }
    _bindSync();
    assert(() {
      checkInvariants();
      return true;
    }());
  }

  /// Binds Downloads and the reader at once, and Playback once Downloads is
  /// bound, because Playback plays Downloads' files.
  void _bindSources() {
    final session = _boundSession = _visibleSession;
    final books = _boundBooks = catalog.books;
    final downloads = this.downloads;
    if (downloads == null) return;
    final generation = ++_generation;
    final reading = reader?.bind(session, books);
    unawaited(() async {
      await downloads.bind(session, books);
      if (generation != _generation) return;
      await playback?.bind(session, books);
      await reading;
    }());
  }

  void _bindSync() {
    sync?.bind(_visibleSession);
    if (catalog.verified) unawaited(sync?.synchronize());
  }
}
