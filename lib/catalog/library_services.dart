import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'book_cover.dart';
import 'book_page.dart' show openBook;
import 'covers.dart';

import '../crossings/crossings.dart';
import '../crossings/scope.dart';
import '../downloads/downloads.dart';
import '../foundation/derived_value.dart';
import '../foundation/listenable_selector.dart';
import '../foundation/theme.dart';
import '../foundation/time.dart';
import '../playback/playback.dart';
import '../playback/screen.dart' show PlaybackMiniPlayer;
import '../reader/scope.dart';
import '../reader/screen.dart';
import '../reader/session.dart';
import 'controller.dart';
import 'layout.dart';
import 'model.dart';
import 'shelf.dart';

/// How the library arranges its entries: as a grid or a list, and how large.
typedef ShelfLayout = ({LibraryView view, LibraryDensity density});

/// What every library screen reads: the catalog, the saved layout, download
/// state, and listening progress. The screens own no copy of this state.
class LibraryServices {
  const LibraryServices({
    required this.catalog,
    required this.layout,
    required this.onReaderNightChanged,
    this.covers,
    this.downloads,
    this.playback,
    this.reader,
    this.crossings,
  });
  final CatalogController catalog;
  final LibraryLayout layout;
  final ValueChanged<bool> onReaderNightChanged;
  final Covers? covers;
  final Downloads? downloads;
  final Playback? playback;
  final ReaderSession? reader;
  final Crossings? crossings;

  /// The saved layout, read only. Equal for the same [layout], so a rebuilt
  /// screen keeps its subscription.
  ValueListenable<ShelfLayout> get shelfLayout => DerivedValue(
    layout,
    () => (view: layout.view, density: layout.density),
    source: layout,
  );

  /// Changes when what the library shows of [book] can change: the download
  /// state of one of its editions, or the listening progress of one of its
  /// audio editions. A player position tick reaches only the book open in
  /// the player, so the parts that show other books do not hear it. While
  /// the book plays or downloads, this changes several times a second, so a
  /// part that listens selects what it shows.
  Listenable bookActivity(Book book) {
    final downloads = this.downloads;
    final playback = this.playback;
    final audio = {
      for (final edition in book.editions)
        if (edition.kind == EditionKind.audio) edition.id,
    };
    return Listenable.merge([
      if (downloads != null)
        for (final edition in book.editions) downloads.watch(edition),
      if (playback != null && audio.isNotEmpty) ...[
        playback.selectionNotifier,
        playback.recordsNotifier,
        _OpenPosition(playback, audio),
      ],
    ]);
  }

  /// Gives covers below [child] the cover store and the current account,
  /// glass panes the book open in the player, and the History sheet the
  /// reader ([ReaderScope]) and the crossings ([CrossingsScope]). A page
  /// pushed on the navigator needs this, because the library's own scope
  /// sits below the navigator.
  Widget pageScope(Widget child) {
    final account = catalog.accountNotifier;
    final selection = playback?.selectionNotifier;
    final reader = this.reader;
    final crossings = this.crossings;
    final scoped = crossings == null
        ? child
        : CrossingsScope(crossings: crossings, child: child);
    return ListenableSelector(
      listenable: Listenable.merge([account, ?selection]),
      select: () => (
        session: account.value.accessBlocked ? null : account.value.session,
        playing: selection?.value.book,
      ),
      builder: (context, scope, child) => CoverScope(
        covers: covers,
        session: scope.session,
        playing: scope.playing,
        child: child!,
      ),
      child: reader == null
          ? scoped
          : ReaderScope(reader: reader, show: showReader, child: scoped),
    );
  }

  /// Brings the reader screen to the front over [context]. While the reader
  /// shows a book, its screen is under [context], so the routes above it
  /// close. Otherwise a new reader screen opens. The caller then opens or
  /// moves the book in [reader], and the screen shows it.
  void showReader(BuildContext context) {
    final navigator = Navigator.of(context);
    // Leaving the reader screen closes its book, so an open book means that
    // the screen is on the navigator.
    if (reader!.book != null) {
      navigator.popUntil(
        (route) => route.settings.name == _readerRoute || route.isFirst,
      );
      return;
    }
    unawaited(
      navigator.push<void>(
        MaterialPageRoute(
          settings: const RouteSettings(name: _readerRoute),
          // The pushed page sits above the library's cover scope, so it
          // brings its own, and the audiobook in its dock shows its cover.
          builder: (_) => pageScope(
            ReaderScreen(
              reader: reader!,
              onNightChanged: onReaderNightChanged,
              playback: playback,
            ),
          ),
        ),
      ),
    );
  }

  /// The name of the reader screen's route.
  static const _readerRoute = 'reader';

  /// A page pushed over the library: [body] on the page surface, with the
  /// mini player floating over its bottom. The player opened from the mini
  /// player offers the book details page. With [extendBodyBehindAppBar], the
  /// body also runs beneath the [appBar].
  Widget page(
    BuildContext context, {
    PreferredSizeWidget? appBar,
    bool extendBodyBehindAppBar = false,
    required Widget body,
  }) => Scaffold(
    extendBodyBehindAppBar: extendBodyBehindAppBar,
    extendBody: true,
    bottomNavigationBar: playback == null
        ? null
        : PlaybackMiniPlayer(
            playback: playback!,
            onOpenBook: (book) => openBook(context, this, book),
          ),
    appBar: appBar,
    body: BookfinSurface(
      child: Material(type: MaterialType.transparency, child: body),
    ),
  );

  bool editionDownloaded(Edition edition) =>
      downloads?.status(edition).phase == DownloadPhase.downloaded;

  bool downloaded(Book book) => bookDownloaded(book, editionDownloaded);

  /// The listening progress of the first audio edition that has one.
  ({int elapsedMs, int totalMs})? progress(Book book) {
    for (final edition in book.editions) {
      if (edition.kind != EditionKind.audio) continue;
      final progress = playback?.progress(edition);
      if (progress != null) return progress;
    }
    return null;
  }

  /// For example "Audio + EPUB · 38% · 6 h 2 m left".
  String summary(Book book) {
    final progress = this.progress(book);
    return [
      formats(book),
      if (progress != null && progress.totalMs > 0)
        progress.totalMs - progress.elapsedMs < 60000
            ? 'finished'
            : '${(progress.elapsedMs * 100 / progress.totalMs).floor()}% · '
                  '${duration(progress.totalMs - progress.elapsedMs)} left',
    ].join(' · ');
  }

  /// For example "1 of 3 downloaded · 1 in progress".
  String seriesSummary(ShelfSeries series) {
    final saved = series.books.where(downloaded).length;
    final started = series.books.where((book) {
      final progress = this.progress(book);
      return progress != null && progress.totalMs - progress.elapsedMs >= 60000;
    }).length;
    return [
      if (saved > 0) '$saved of ${series.books.length} downloaded',
      if (started > 0) '$started in progress',
    ].join(' · ');
  }
}

/// For example "Audio + EPUB", or "PDF" for a book with one PDF edition.
String formats(Book book) {
  final text = {
    for (final edition in book.editions)
      if (edition.kind == EditionKind.text)
        for (final file in edition.files)
          if (file.container.isNotEmpty) file.container.toUpperCase(),
  };
  return [
    if (book.editions.any((edition) => edition.kind == EditionKind.audio))
      'Audio',
    if (text.isEmpty &&
        book.editions.any((edition) => edition.kind == EditionKind.text))
      'Ebook',
    ...text,
  ].join(' + ');
}

String seriesPosition(double order) => order == order.truncateToDouble()
    ? order.toInt().toString()
    : order.toString();

/// [Playback.positionNotifier], heard only while one of [editions] is open
/// in the player.
class _OpenPosition implements Listenable {
  _OpenPosition(this.playback, this.editions);
  final Playback playback;

  /// Edition ids.
  final Set<String> editions;

  /// The listener that each added listener is wrapped in.
  final _gates = <VoidCallback, VoidCallback>{};

  @override
  void addListener(VoidCallback listener) {
    void gate() {
      if (editions.contains(playback.selectionNotifier.value.edition?.id)) {
        listener();
      }
    }

    // One gate for each listener, so a second add leaks no gate.
    removeListener(listener);
    _gates[listener] = gate;
    playback.positionNotifier.addListener(gate);
  }

  @override
  void removeListener(VoidCallback listener) {
    final gate = _gates.remove(listener);
    if (gate != null) playback.positionNotifier.removeListener(gate);
  }
}
