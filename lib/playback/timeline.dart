import 'dart:async';

import 'package:flutter/material.dart';

import '../catalog/glass.dart';
import '../catalog/library_services.dart' show duration;
import '../catalog/model.dart';
import '../foundation/theme.dart';
import 'playback.dart';
import 'recent.dart' show listenedWhen;
import 'records_screen.dart';

/// Opens the listening timeline of [book] on a glass sheet. Without a book,
/// the timeline shows every book and names the book of each entry.
void openListeningTimeline(
  BuildContext context,
  Playback playback, {
  Book? book,
}) => unawaited(
  showGlassSheet<void>(
    context,
    book: book,
    isScrollControlled: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, scroll) =>
          ListeningTimeline(playback: playback, book: book, scroll: scroll),
    ),
  ),
);

/// One moment in listening: an action or a bookmark.
sealed class TimelineEntry {
  const TimelineEntry();
  String get id;
  DateTime get at;
  String get bookTitle;
}

final class ActionEntry extends TimelineEntry {
  const ActionEntry(this.event);
  final ListeningEvent event;
  @override
  String get id => event.id;
  @override
  DateTime get at => event.at;
  @override
  String get bookTitle => event.bookTitle;
}

final class BookmarkEntry extends TimelineEntry {
  const BookmarkEntry(this.bookmark);
  final AudioBookmark bookmark;
  @override
  String get id => bookmark.id;
  @override
  DateTime get at => bookmark.createdAt;
  @override
  String get bookTitle => bookmark.bookTitle;
}

/// The actions and bookmarks of [book], or of every book, newest first.
List<TimelineEntry> timelineOf(Playback playback, Book? book) {
  bool belongs(AudioPosition place) =>
      book == null ||
      book.editions.any((edition) => edition.id == place.editionId);
  return [
    for (final event in playback.history)
      if (belongs(event.after)) ActionEntry(event),
    for (final bookmark in playback.bookmarks)
      if (belongs(bookmark.position)) BookmarkEntry(bookmark),
  ]..sort((a, b) => b.at.compareTo(a.at));
}

/// A dense, vertical timeline of listening, grouped by day. A tap on an
/// entry shows the places it can return to, and Delete.
class ListeningTimeline extends StatefulWidget {
  const ListeningTimeline({
    super.key,
    required this.playback,
    this.book,
    this.scroll,
  });
  final Playback playback;
  final Book? book;
  final ScrollController? scroll;

  @override
  State<ListeningTimeline> createState() => _ListeningTimelineState();
}

/// The width of the time of day column, wide enough for "12:59 PM" on one
/// line.
const _timeWidth = 60.0;

class _ListeningTimelineState extends State<ListeningTimeline> {
  /// The entry whose choices are shown, if any.
  String? _open;

  Playback get playback => widget.playback;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: playback,
    builder: (context, _) {
      final theme = Theme.of(context);
      final entries = timelineOf(playback, widget.book);
      final now = DateTime.now();
      String? day;
      return ListView(
        controller: widget.scroll,
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + floatingBarInset(context)),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
            child: Text(
              'History',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontFamily: 'Source Serif 4',
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          RecordSaveStatus(playback: playback),
          if (entries.isEmpty)
            const Padding(
              padding: EdgeInsets.all(4),
              child: Text(
                'Nothing yet. Jumps, pauses and bookmarks appear here.',
              ),
            ),
          for (final entry in entries) ...[
            if (listenedWhen(entry.at.toLocal(), now) != day)
              _DayLabel(day = listenedWhen(entry.at.toLocal(), now)),
            _row(context, entry),
          ],
        ],
      );
    },
  );

  Widget _row(BuildContext context, TimelineEntry entry) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = theme.brightness == Brightness.dark
        ? theaterGlow
        : scheme.primary;
    final small = TextStyle(
      fontSize: 12,
      color: scheme.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final open = _open == entry.id;
    final (label, place) = switch (entry) {
      ActionEntry(:final event) => (_label(event), event.after),
      BookmarkEntry(:final bookmark) => (
        bookmark.title ?? 'Bookmark',
        bookmark.position,
      ),
    };
    final time = MaterialLocalizations.of(context)
        .formatTimeOfDay(TimeOfDay.fromDateTime(entry.at.toLocal()));
    return Stack(
      children: [
        // The rail that joins the entries of a day.
        Positioned(
          left: _timeWidth + 11.25,
          top: 0,
          bottom: 0,
          child: Container(width: 1.5, color: scheme.outlineVariant),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(() => _open = open ? null : entry.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: _timeWidth,
                      child: Text(
                        time,
                        style: small,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.fade,
                        textAlign: TextAlign.right,
                      ),
                    ),
                    SizedBox(
                      width: 24,
                      child: Center(
                        child: entry is BookmarkEntry
                            ? Icon(
                                Icons.bookmark_rounded,
                                size: 13,
                                color: accent,
                              )
                            : Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: open
                                      ? accent
                                      : scheme.onSurfaceVariant,
                                ),
                              ),
                      ),
                    ),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          text: label,
                          children: [
                            if (widget.book == null)
                              TextSpan(
                                text: ' · ${entry.bookTitle}',
                                style: small,
                              ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(_place(place), style: small),
                  ],
                ),
              ),
            ),
            if (open)
              Padding(
                padding: const EdgeInsets.only(
                  left: _timeWidth + 20,
                  bottom: 4,
                ),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 4,
                  children: [..._choices(context, entry)],
                ),
              ),
          ],
        ),
      ],
    );
  }

  List<Widget> _choices(BuildContext context, TimelineEntry entry) {
    // A choice that goes to a place closes the timeline, so the player shows
    // that place and offers Undo.
    Widget choice(
      String text,
      Future<void> Function() go, {
      bool goes = true,
    }) => TextButton(
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 10),
      ),
      onPressed: () {
        if (goes) Navigator.pop(context);
        unawaited(go());
      },
      child: Text(text),
    );
    final delete = IconButton(
      tooltip: 'Delete',
      visualDensity: VisualDensity.compact,
      icon: const Icon(Icons.delete_outline, size: 20),
      onPressed: () => unawaited(_delete(context, entry)),
    );
    return switch (entry) {
      ActionEntry(:final event) => [
        if (event.changesPosition)
          choice(
            'Go back to ${_place(event.before)}',
            () => playback.restoreHistory(event.id),
          ),
        choice(
          'Go to ${_place(event.after)}',
          () => playback.restoreHistory(event.id, previous: false),
        ),
        delete,
      ],
      BookmarkEntry(:final bookmark) => [
        choice(
          'Go to ${_place(bookmark.position)}',
          () => playback.restoreBookmark(bookmark.id),
        ),
        choice(
          bookmark.title == null ? 'Name' : 'Rename',
          () => editAudioBookmark(context, playback, bookmark: bookmark),
          goes: false,
        ),
        delete,
      ],
    };
  }

  Future<void> _delete(BuildContext context, TimelineEntry entry) async {
    final (title, explanation, remove) = switch (entry) {
      ActionEntry(:final event) => (
        'Delete history action?',
        'Remove this action from your history on synced devices. Bookmarks and other actions stay.',
        () => playback.deleteHistory(event.id),
      ),
      BookmarkEntry(:final bookmark) => (
        'Delete bookmark?',
        'Remove this bookmark on synced devices. Other bookmarks and your history stay.',
        () => playback.deleteBookmark(bookmark.id),
      ),
    };
    await showDialog<void>(
      context: context,
      builder: (context) => GlassDialog(
        title: Text(title),
        content: Text(explanation),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await remove();
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  /// A place as a time in its edition, or in its file when the edition time
  /// is unknown.
  String _place(AudioPosition place) =>
      audioTime(playback.editionTime(place) ?? place.milliseconds);

  String _label(ListeningEvent event) {
    final from = playback.editionTime(event.before);
    final to = playback.editionTime(event.after);
    String moved(String verb) {
      if (from == null || to == null) return verb;
      final distance = (to - from).abs();
      final span = distance < 60000
          ? '${(distance / 1000).round()} s'
          : duration(distance);
      return '$verb ${to >= from ? 'ahead' : 'back'} $span';
    }

    return switch (event.kind) {
      ListeningAction.seek => moved('Moved'),
      ListeningAction.jump => moved('Jumped'),
      ListeningAction.chapter => 'Changed chapter',
      ListeningAction.undo => 'Undid a move',
      ListeningAction.historyRestore => 'Went back in history',
      ListeningAction.bookmarkRestore => 'Went to a bookmark',
      ListeningAction.pause => 'Paused',
      ListeningAction.resume => 'Played',
      ListeningAction.interruption => 'Interrupted',
      ListeningAction.stop => 'Stopped',
      ListeningAction.completion => 'Finished',
    };
  }
}

class _DayLabel extends StatelessWidget {
  const _DayLabel(this.day);
  final String day;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 14, 4, 4),
    child: Text(
      day,
      style: TextStyle(
        fontSize: 12,
        letterSpacing: 0.4,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}
