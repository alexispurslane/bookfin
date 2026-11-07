import 'package:flutter/material.dart';

import '../catalog/book_cover.dart';
import '../catalog/library_view.dart' show BookRow;
import '../foundation/theme.dart';
import '../foundation/time.dart';
import 'playback.dart';

/// Books listened to recently, newest first. The open book is left out,
/// because the player above shows it. A tap reports the book to resume.
class RecentListeningList extends StatelessWidget {
  const RecentListeningList({
    super.key,
    required this.playback,
    required this.onResume,
    this.empty = const SizedBox.shrink(),
  });
  final Playback playback;

  /// Reports a tap on a book, which asks to resume it where it stopped.
  final ValueChanged<RecentListening> onResume;

  /// Shown instead when no other book was listened to.
  final Widget empty;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    // The list follows the records, and leaves out the open book.
    listenable: Listenable.merge([
      playback.recordsNotifier,
      playback.selectionNotifier,
    ]),
    builder: (context, _) {
      final recent = [
        for (final entry in playback.recent)
          if (entry.book.id != playback.book?.id) entry,
      ];
      if (recent.isEmpty) return empty;
      final now = DateTime.now();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: const SectionLabel('RECENTLY LISTENED'),
          ),
          for (final entry in recent)
            RecentListeningRow(
              entry: entry,
              progress: playback.progress(entry.edition),
              now: now,
              onResume: onResume,
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
  });
  final RecentListening entry;

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
    return BookRow(
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
  }
}
