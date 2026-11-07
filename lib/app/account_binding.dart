import 'dart:async';

import '../catalog/controller.dart';
import '../catalog/model.dart';
import '../downloads/downloads.dart';
import '../playback/playback.dart';
import '../reader/session.dart';
import '../sync/coordinator.dart';

/// Hands the catalog's account and books to every source that works for one
/// account: Downloads, Playback, the reader and record sync. It binds them
/// when it starts, and again whenever the visible account or the book list
/// changes. Blocked library access shows as no account. After each sign-in
/// or refresh that succeeds, it asks record sync to run.
///
/// It wakes only on the catalog's narrow signals: the account and the
/// library for the binding, and the status for record sync. A refresh that
/// brings the same account and books binds nothing.
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
    catalog.accountNotifier.addListener(_accountOrBooksChanged);
    catalog.libraryNotifier.addListener(_accountOrBooksChanged);
    catalog.statusNotifier.addListener(_statusChanged);
    _bind();
    _statusChanged();
  }

  final CatalogController catalog;
  final Downloads? downloads;
  final Playback? playback;
  final ReaderSession? reader;
  final RecordSync? sync;

  /// The account and books last handed to the sources. The account holds
  /// only the session that the sources use, and equals another account with
  /// an equal session, so a refresh that validates the same session again
  /// does not count as a new account.
  CatalogAccount? _boundAccount;
  List<Book>? _boundBooks;

  /// The account of [_boundAccount], or of the catalog when access is
  /// blocked, to tell a new account from blocked access.
  String? _accountKey;

  /// Counts bindings, so that a binding that a newer one replaced stops.
  int _generation = 0;
  bool _disposed = false;

  // The catalog sets its signals one after another, so the listener of one
  // signal can see the old value of another: at sign-out, the empty library
  // comes before the account without a session. Its getters hold the new
  // state of every signal, so the binding reads them.
  CatalogAccount get _visibleAccount =>
      CatalogAccount(session: catalog.accessBlocked ? null : catalog.session);

  void checkInvariants() {
    if (_disposed) return;
    if (_boundAccount != _visibleAccount ||
        !identical(_boundBooks, catalog.books)) {
      throw StateError('The sources hold an account or books that changed.');
    }
  }

  /// Stops following the catalog. A binding in progress stops before its
  /// next source.
  void dispose() {
    _disposed = true;
    _generation++;
    catalog.accountNotifier.removeListener(_accountOrBooksChanged);
    catalog.libraryNotifier.removeListener(_accountOrBooksChanged);
    catalog.statusNotifier.removeListener(_statusChanged);
  }

  void _accountOrBooksChanged() {
    // One catalog change can change both signals; the second finds the
    // sources bound already.
    if (_boundAccount != _visibleAccount ||
        !identical(_boundBooks, catalog.books)) {
      final key = catalog.session?.scope.key;
      if (_accountKey != key || catalog.accessBlocked) {
        // The open book and the open publication belong to the old account,
        // so they close before the new account's binding starts.
        unawaited(playback?.bind(null, []));
        unawaited(reader?.bind(null, []));
      }
      _accountKey = key;
      _bind();
    }
    assert(() {
      checkInvariants();
      return true;
    }());
  }

  /// Only a sign-in or a refresh that succeeds sets verified, and each one
  /// ends with a status change.
  void _statusChanged() {
    if (catalog.verified) unawaited(sync?.synchronize());
  }

  /// Binds Downloads and the reader at once, and Playback once Downloads is
  /// bound, because Playback plays Downloads' files. Binds record sync when
  /// the account changed.
  void _bind() {
    final account = _visibleAccount;
    final books = _boundBooks = catalog.books;
    if (_boundAccount != account) sync?.bind(account.session);
    _boundAccount = account;
    final session = account.session;
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
}
