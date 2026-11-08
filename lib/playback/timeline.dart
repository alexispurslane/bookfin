import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../catalog/glass.dart';
import '../catalog/model.dart';
import '../foundation/derived_value.dart';
import '../foundation/theme.dart';
import '../foundation/time.dart';
import 'playback.dart';
import 'records_screen.dart';

// openListeningTimeline is the controller of the timeline sheet. It wires
// ListeningTimeline, which only draws entries and reports choices, to
// Playback: it confirms a delete, closes the sheet before a jump, and names
// a bookmark through the shared bookmark editor.

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
    title: 'History',
    isScrollControlled: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, scroll) {
        // A choice that goes to a place closes the timeline, so the player
        // shows that place and offers Undo.
        void go(Future<void> Function() restore) {
          Navigator.pop(context);
          unawaited(restore());
        }

        return ListeningTimeline(
          // The rows show labels and places measured from the library, so
          // the entries follow the records and the library. A playing tick
          // does not reach the timeline.
          entries: DerivedValue(
            Listenable.merge([
              playback.recordsNotifier,
              playback.libraryNotifier,
            ]),
            () => playback.timeline(book),
          ),
          editionTime: playback.editionTime,
          showBooks: book == null,
          header: RecordSaveStatus(playback: playback),
          scroll: scroll,
          onGoBack: (event) => go(() => playback.restoreHistory(event.id)),
          onGoTo: (entry) => go(
            () => switch (entry) {
              ActionEntry(:final event) => playback.restoreHistory(
                event.id,
                previous: false,
              ),
              BookmarkEntry(:final bookmark) => playback.restoreBookmark(
                bookmark.id,
              ),
            },
          ),
          onRename: (bookmark) => unawaited(
            editAudioBookmark(context, playback, bookmark: bookmark),
          ),
          onDelete: (entry) =>
              unawaited(_confirmDelete(context, playback, entry)),
        );
      },
    ),
  ),
);

/// Asks the listener to confirm the deletion of [entry], then deletes it
/// from [playback]. Nothing changes when the listener cancels.
Future<void> _confirmDelete(
  BuildContext context,
  Playback playback,
  TimelineEntry entry,
) async {
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
  if (await confirmAction(
    context,
    title: title,
    message: explanation,
    action: 'Delete',
  )) {
    await remove();
  }
}

/// A dense, vertical timeline of listening, grouped by day. A tap on an
/// entry shows the places it can return to, and Delete. The timeline changes
/// no records itself: it reports each choice through its callbacks.
class ListeningTimeline extends StatefulWidget {
  const ListeningTimeline({
    super.key,
    required this.entries,
    required this.editionTime,
    this.showBooks = false,
    this.header,
    this.scroll,
    required this.onGoBack,
    required this.onGoTo,
    required this.onRename,
    required this.onDelete,
  });

  /// The actions and bookmarks to show, newest first.
  final ValueListenable<List<TimelineEntry>> entries;

  /// Where a place is in its audio edition, in milliseconds from the
  /// edition's start, or null when that is unknown.
  final int? Function(AudioPosition place) editionTime;

  /// Whether each entry names its book, for a timeline of every book.
  final bool showBooks;

  /// Shown above the entries, such as the save status of the records.
  final Widget? header;
  final ScrollController? scroll;

  /// Reports Go back on an action: return to where [ListeningEvent.before]
  /// says the action began.
  final ValueChanged<ListeningEvent> onGoBack;

  /// Reports Go to: return to where an action ended, or to a bookmark.
  final ValueChanged<TimelineEntry> onGoTo;

  /// Reports Name or Rename on a bookmark.
  final ValueChanged<AudioBookmark> onRename;

  /// Reports Delete on an entry. The listener has not confirmed it yet.
  final ValueChanged<TimelineEntry> onDelete;

  @override
  State<ListeningTimeline> createState() => _ListeningTimelineState();
}

/// The width of the time of day column, wide enough for "12:59 PM" on one
/// line.
const _timeWidth = 68.0;

class _ListeningTimelineState extends State<ListeningTimeline> {
  /// The entry whose choices are shown, if any.
  String? _open;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: widget.entries,
    builder: (context, entries, _) {
      final now = DateTime.now();
      String day(int index) => listenedWhen(entries[index].at.toLocal(), now);
      // Only the rows near the screen are built, because a history can hold
      // thousands of entries.
      return ListView.builder(
        controller: widget.scroll,
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + floatingBarInset(context)),
        // The header, then the entries or a note that there are none.
        itemCount: 1 + (entries.isEmpty ? 1 : entries.length),
        itemBuilder: (context, index) => switch (index - 1) {
          -1 => widget.header ?? const SizedBox.shrink(),
          _ when entries.isEmpty => const Padding(
            padding: EdgeInsets.all(4),
            child: Text(
              'Nothing yet. Jumps, pauses and bookmarks appear here.',
            ),
          ),
          final row when row == 0 || day(row) != day(row - 1) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [_DayLabel(day(row)), _row(context, entries[row])],
          ),
          final row => _row(context, entries[row]),
        },
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
                            if (widget.showBooks)
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
                  children: [..._choices(entry)],
                ),
              ),
          ],
        ),
      ],
    );
  }

  List<Widget> _choices(TimelineEntry entry) {
    Widget choice(String text, VoidCallback report) => TextButton(
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 10),
      ),
      onPressed: report,
      child: Text(text),
    );
    final delete = IconButton(
      tooltip: 'Delete',
      visualDensity: VisualDensity.compact,
      icon: const Icon(Icons.delete_outline, size: 20),
      onPressed: () => widget.onDelete(entry),
    );
    return switch (entry) {
      ActionEntry(:final event) => [
        if (event.changesPosition)
          choice(
            'Go back to ${_place(event.before)}',
            () => widget.onGoBack(event),
          ),
        choice('Go to ${_place(event.after)}', () => widget.onGoTo(entry)),
        delete,
      ],
      BookmarkEntry(:final bookmark) => [
        choice(
          'Go to ${_place(bookmark.position)}',
          () => widget.onGoTo(entry),
        ),
        choice(
          bookmark.title == null ? 'Name' : 'Rename',
          () => widget.onRename(bookmark),
        ),
        delete,
      ],
    };
  }

  /// A place as a time in its edition, or in its file when the edition time
  /// is unknown.
  String _place(AudioPosition place) =>
      audioTime(widget.editionTime(place) ?? place.milliseconds);

  String _label(ListeningEvent event) {
    final from = widget.editionTime(event.before);
    final to = widget.editionTime(event.after);
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
