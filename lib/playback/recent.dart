import 'dart:async';

import 'package:flutter/material.dart';

import '../catalog/book_cover.dart';
import '../catalog/library_view.dart' show BookRow;
import '../foundation/theme.dart';
import '../foundation/time.dart';
import 'playback.dart';

/// Books listened to recently, newest first. A tap resumes a book where it
/// stopped. The open book is left out, because the player above shows it.
class RecentListeningList extends StatelessWidget {
  const RecentListeningList({super.key, required this.playback});
  final Playback playback;

  @override
  Widget build(BuildContext context) {
    final recent = [
      for (final entry in playback.recent)
        if (entry.book.id != playback.book?.id) entry,
    ];
    if (recent.isEmpty) return const SizedBox.shrink();
    final now = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: const SectionLabel('RECENTLY LISTENED'),
        ),
        for (final entry in recent)
          _RecentRow(playback: playback, entry: entry, now: now),
      ],
    );
  }
}

class _RecentRow extends StatelessWidget {
  const _RecentRow({
    required this.playback,
    required this.entry,
    required this.now,
  });
  final Playback playback;
  final RecentListening entry;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final progress = playback.progress(entry.edition);
    final left = progress == null
        ? null
        : progress.totalMs - progress.elapsedMs;
    void resume() => unawaited(playback.open(entry.book, entry.edition));
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
