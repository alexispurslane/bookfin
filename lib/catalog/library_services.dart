import 'package:flutter/widgets.dart';

import 'book_cover.dart';
import 'covers.dart';

import '../downloads/downloads.dart';
import '../playback/playback.dart';
import '../reader/session.dart';
import 'controller.dart';
import 'layout.dart';
import 'model.dart';
import 'shelf.dart';

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
  });
  final CatalogController catalog;
  final LibraryLayout layout;
  final ValueChanged<bool> onReaderNightChanged;
  final Covers? covers;
  final Downloads? downloads;
  final Playback? playback;
  final ReaderSession? reader;

  /// Changes whenever a library screen can look different.
  Listenable get changes =>
      Listenable.merge([catalog, layout, ?downloads, ?playback]);

  /// Gives covers below [child] the cover store and the current account.
  /// A page pushed on the navigator needs this, because the library's own
  /// scope sits below the navigator.
  Widget coverScope(Widget child) => ListenableBuilder(
    listenable: catalog,
    builder: (context, child) => CoverScope(
      covers: covers,
      session: catalog.accessBlocked ? null : catalog.session,
      child: child!,
    ),
    child: child,
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

/// For example "9 h 44 m", or "12 m" under one hour.
String duration(int milliseconds) {
  final minutes = (milliseconds / 60000).round();
  return minutes < 60 ? '$minutes m' : '${minutes ~/ 60} h ${minutes % 60} m';
}

String seriesPosition(double order) => order == order.truncateToDouble()
    ? order.toInt().toString()
    : order.toString();
