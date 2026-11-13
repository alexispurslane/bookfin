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
/// changes. Blocked library access shows as no account. Record sync decides
/// on its own when it syncs the account that it is bound to, so a catalog
/// change that keeps the account starts no sync.
///
/// It wakes only on the catalog's narrow signals: the account and the
/// library. A refresh that brings the same account and books binds nothing.
///
/// Only a new account or blocked access unbinds the sources. A refresh that
/// cannot reach the server changes neither, so the saved library, saved
/// places and history stay bound. Rejected credentials also keep local
/// sources bound; each server worker follows the shared credential signal.
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
    _bind();
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

  bool _disposed = false;

  // The catalog sets its signals one after another, so the listener of one
  // signal can see the old value of another: at sign-out, the empty library
  // comes before the account without a session. Its getters hold the new
  // state of every signal, so the binding reads them for the account and
  // the books.
  CatalogAccount get _visibleAccount => CatalogAccount(
    session: catalog.accessBlocked ? null : catalog.session,
    needsSignIn: catalog.session?.needsSignIn ?? false,
  );

  void checkInvariants() {
    if (_disposed) return;
    if (_boundAccount != _visibleAccount ||
        !identical(_boundBooks, catalog.books)) {
      throw StateError('The sources hold an account or books that changed.');
    }
  }

  /// Stops following the catalog. Sources own bindings already started.
  void dispose() {
    _disposed = true;
    catalog.accountNotifier.removeListener(_accountOrBooksChanged);
    catalog.libraryNotifier.removeListener(_accountOrBooksChanged);
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

  /// Starts each binding at once. Downloads owns readiness of each file,
  /// so Playback can restore its book while unrelated downloads restore.
  /// Binds record sync when the account changed.
  void _bind() {
    final account = _visibleAccount;
    final books = _boundBooks = catalog.books;
    if (_boundAccount != account) sync?.bind(account.session);
    _boundAccount = account;
    final session = account.session;
    final downloads = this.downloads;
    if (downloads == null) return;
    final reading = reader?.bind(session, books);
    unawaited(
      Future.wait<void>([
        downloads.bind(session, books),
        if (playback != null) playback!.bind(session, books),
        ?reading,
      ]),
    );
  }
}
