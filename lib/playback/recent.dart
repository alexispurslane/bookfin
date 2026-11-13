import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../catalog/book_cover.dart';
import '../catalog/library_view.dart' show BookRow;
import '../catalog/model.dart';
import '../foundation/derived_value.dart';
import '../foundation/theme.dart';
import '../foundation/time.dart';
import 'playback.dart';

/// A recently listened book, and where its saved place is in the edition,
/// or null when that is unknown.
typedef RecentProgress = ({
  RecentListening entry,
  ({int elapsedMs, int totalMs})? progress,
});

/// The recent listening of [playback], newest first, each book with its
/// progress. It notifies when the records, the open book or the library
/// change, because the rows show books and lengths from the library. A
/// playing tick does not reach it. Equal for the same [playback], so a
/// rebuilt owner keeps its subscription.
ValueListenable<List<RecentProgress>> recentProgress(Playback playback) =>
    DerivedValue(
      Listenable.merge([
        playback.recordsNotifier,
        playback.selectionNotifier,
        playback.libraryNotifier,
      ]),
      () => [
        for (final entry in playback.recent)
          (entry: entry, progress: playback.progress(entry.edition)),
      ],
      source: playback,
    );

/// Books listened to recently, newest first, under a RECENTLY LISTENED
/// label. The [open] book is left out, because the player above shows it.
/// A tap reports the book to resume.
class RecentListeningList extends StatelessWidget {
  const RecentListeningList({
    super.key,
    required this.recent,
    required this.open,
    required this.onResume,
    this.empty = const SizedBox.shrink(),
    this.noticeBuilder,
  });

  /// The recently listened books, newest first, with their progress.
  final ValueListenable<List<RecentProgress>> recent;

  /// The book open in the player, or null when none is open.
  final Book? open;

  /// Reports a tap on a book, which asks to resume it where it stopped.
  final ValueChanged<RecentListening> onResume;

  /// Shown instead when no other book was listened to.
  final Widget empty;

  /// A scoped action notice beside the book that was asked to resume.
  final Widget Function(RecentListening)? noticeBuilder;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: recent,
    builder: (context, recent, _) {
      final shown = [
        for (final item in recent)
          if (item.entry.book.id != open?.id) item,
      ];
      if (shown.isEmpty) return empty;
      final now = DateTime.now();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: const SectionLabel('RECENTLY LISTENED'),
          ),
          for (final (:entry, :progress) in shown)
            RecentListeningRow(
              entry: entry,
              progress: progress,
              now: now,
              onResume: onResume,
              notice: noticeBuilder?.call(entry),
            ),
        ],
      );
    },
  );
}

/// One recently listened book: when it was listened to, the time left, and
/// a progress line.
class RecentListeningRow extends StatelessWidget {
  const RecentListeningRow({
    super.key,
    required this.entry,
    required this.progress,
    required this.now,
    required this.onResume,
    this.notice,
  });
  final RecentListening entry;

  /// The action notice supplied by the controller for this edition.
  final Widget? notice;

  /// Where the saved place is in the edition, or null when unknown.
  final ({int elapsedMs, int totalMs})? progress;

  /// The time that the day of [entry] is named against.
  final DateTime now;

  /// Reports a tap with [entry].
  final ValueChanged<RecentListening> onResume;

  @override
  Widget build(BuildContext context) {
    final progress = this.progress;
    final left = progress == null
        ? null
        : progress.totalMs - progress.elapsedMs;
    void resume() => onResume(entry);
    final row = BookRow(
      compact: true,
      cover: BookCover.book(entry.book, showText: false),
      title: entry.book.title,
      author: entry.book.author,
      detail: [
        listenedWhen(entry.at, now),
        if (left != null && progress!.totalMs > 0)
          left < 60000 ? 'finished' : '${duration(left)} left',
      ].join(' · '),
      below: progress == null || progress.totalMs <= 0
          ? null
          : ProgressLine(value: progress.elapsedMs / progress.totalMs),
      onTap: resume,
      semanticLabel: 'Resume ${entry.book.title}',
      trailing: IconButton(
        tooltip: 'Resume ${entry.book.title}',
        onPressed: resume,
        icon: const Icon(Icons.play_circle_outline_rounded),
      ),
    );
    // BookRow replaces its children's semantics with the Resume label.
    // Keep the live error outside that button so assistive readers hear it.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [row, ?notice],
    );
  }
}
