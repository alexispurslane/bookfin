import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../catalog/glass.dart';
import '../catalog/model.dart';
import '../foundation/derived_value.dart';
import '../foundation/theme.dart';
import '../foundation/time.dart';
import '../reader/scope.dart';
import 'playback.dart';
import 'records_screen.dart';
import 'screen.dart' show openPlayer;

// openHistory is the controller of the timeline sheet. It wires
// HistoryTimeline, which only draws entries and reports choices, to the
// owners of the places: Playback for listening, and the reader session of
// the ReaderScope for reading. It routes each choice to the owner of its
// place, confirms a delete, closes the sheet before a jump, shows the
// screen of the place's medium, and names a bookmark through the shared
// bookmark editor.

/// Opens the History of [book] on a glass sheet: the listening moves and
/// bookmarks of [playback] and, under a [ReaderScope], the reading moves
/// and bookmarks of its reader, together, newest first. Without a book, the
/// timeline shows every book and names the book of each entry.
///
/// [showing] is the medium of the screen under the sheet: audio in the
/// player, text in the reader, and null elsewhere, such as on the book
/// page. Go to on an entry of another medium also shows the player or the
/// reader at that place.
void openHistory(
  BuildContext context,
  Playback? playback, {
  Book? book,
  EditionKind? showing,
}) {
  final reading = ReaderScope.maybeOf(context);
  final reader = reading?.reader;
  unawaited(
    showGlassSheet<void>(
      context,
      book: book,
      title: 'History',
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (sheet, scroll) {
          // A choice that goes to a place closes the timeline, so the screen
          // of the place's medium shows it and offers Undo.
          void go(Place place, Future<void> Function() restore) {
            Navigator.pop(sheet);
            switch (place) {
              case AudioPosition() when showing == EditionKind.audio:
                unawaited(restore());
              case AudioPosition():
                unawaited(() async {
                  await restore();
                  if (context.mounted) openPlayer(context, playback!);
                }());
              case TextPosition():
                // The reader shows a place of its open edition, and opens
                // the edition of any other place there.
                final open = reader!.edition?.id == place.editionId;
                if (showing != EditionKind.text) reading!.show(context);
                unawaited(open ? restore() : reader.openAt(place));
            }
          }

          return HistoryTimeline(
            // The rows show labels and places measured from the library and
            // from the open book's map, so the entries follow the records,
            // the library, the open book and its pages. A playing tick does
            // not reach the timeline.
            entries: DerivedValue(
              Listenable.merge([
                if (playback != null) ...[
                  playback.recordsNotifier,
                  playback.libraryNotifier,
                ],
                if (reader != null) ...[
                  reader.historyChanges,
                  reader.bookmarkChanges,
                  reader.documentChanges,
                  reader.bookMapChanges,
                ],
              ]),
              () => _newestFirst(
                playback?.timeline(book) ?? const [],
                reader?.timeline(book) ?? const [],
              ),
            ),
            describe: (place) => switch (place) {
              AudioPosition() => playback!.describe(place),
              TextPosition() => reader!.describe(place),
            },
            showBooks: book == null,
            header: RecordSaveStatus(playback: playback, reader: reader),
            scroll: scroll,
            onGoBack: (event) => go(
              event.before,
              () => switch (event.before) {
                AudioPosition() => playback!.restoreHistory(event.id),
                TextPosition() => reader!.restoreHistory(event.id),
              },
            ),
            onGoTo: (entry) => switch (entry) {
              ActionEntry(:final event) => go(
                event.after,
                () => switch (event.after) {
                  AudioPosition() => playback!.restoreHistory(
                    event.id,
                    previous: false,
                  ),
                  TextPosition() => reader!.restoreHistory(
                    event.id,
                    previous: false,
                  ),
                },
              ),
              BookmarkEntry(:final bookmark) => go(
                bookmark.position,
                () => switch (bookmark.position) {
                  AudioPosition() => playback!.restoreBookmark(bookmark.id),
                  TextPosition() => reader!.restoreBookmark(bookmark.id),
                },
              ),
            },
            onRename: (bookmark) => unawaited(switch (bookmark) {
              final Bookmark<AudioPosition> bookmark => editAudioBookmark(
                sheet,
                playback!,
                bookmark: bookmark,
              ),
              final Bookmark<TextPosition> bookmark => editReadingBookmark(
                sheet,
                reader!,
                bookmark,
              ),
              _ => Future.value(),
            }),
            onDelete: (entry) => unawaited(
              _confirmDelete(sheet, entry, switch (entry) {
                ActionEntry(:final event) => switch (event.after) {
                  AudioPosition() => () => playback!.deleteHistory(event.id),
                  TextPosition() => () => reader!.deleteHistory(event.id),
                },
                BookmarkEntry(:final bookmark) => switch (bookmark.position) {
                  AudioPosition() => () => playback!.deleteBookmark(
                    bookmark.id,
                  ),
                  TextPosition() => () => reader!.deleteBookmark(bookmark.id),
                },
              }),
            ),
          );
        },
      ),
    ),
  );
}

/// The entries of [first] and [second], each newest first, in one list,
/// newest first.
List<TimelineEntry> _newestFirst(
  List<TimelineEntry> first,
  List<TimelineEntry> second,
) {
  if (first.isEmpty) return second;
  if (second.isEmpty) return first;
  final merged = <TimelineEntry>[];
  var (a, b) = (0, 0);
  while (a < first.length && b < second.length) {
    merged.add(first[a].at.isBefore(second[b].at) ? second[b++] : first[a++]);
  }
  return merged
    ..addAll(first.skip(a))
    ..addAll(second.skip(b));
}

/// Asks the person to confirm the deletion of [entry], then deletes it with
/// [remove]. Nothing changes when the person cancels.
Future<void> _confirmDelete(
  BuildContext context,
  TimelineEntry entry,
  Future<void> Function() remove,
) async {
  final (title, explanation) = switch (entry) {
    ActionEntry() => (
      'Delete history action?',
      'Remove this action from your history on synced devices. Bookmarks and other actions stay.',
    ),
    BookmarkEntry() => (
      'Delete bookmark?',
      'Remove this bookmark on synced devices. Other bookmarks and your history stay.',
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

/// A dense, vertical timeline of listening and reading, grouped by day. A
/// tap on an entry shows where its place is, the places it can return to,
/// and Delete. When the entries hold both media, a glyph on the rail marks
/// the medium of each entry. The timeline changes no records itself: it
/// reports each choice through its callbacks.
class HistoryTimeline extends StatefulWidget {
  const HistoryTimeline({
    super.key,
    required this.entries,
    required this.describe,
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

  /// A place in words, such as `Playback.describe` for a listening place
  /// and `ReaderSession.describe` for a reading place. A row asks for it
  /// each time that it builds, because a reading place's page number
  /// changes with the text size.
  final PlaceWords Function(Place place) describe;

  /// Whether each entry names its book, for a timeline of every book.
  final bool showBooks;

  /// Shown above the entries, such as the save status of the records.
  final Widget? header;
  final ScrollController? scroll;

  /// Reports Go back on an action: return to where [HistoryEvent.before]
  /// says the action began.
  final ValueChanged<HistoryEvent<Place>> onGoBack;

  /// Reports Go to: return to where an action ended, or to a bookmark.
  final ValueChanged<TimelineEntry> onGoTo;

  /// Reports Name or Rename on a bookmark.
  final ValueChanged<Bookmark<Place>> onRename;

  /// Reports Delete on an entry. The listener has not confirmed it yet.
  final ValueChanged<TimelineEntry> onDelete;

  @override
  State<HistoryTimeline> createState() => _HistoryTimelineState();
}

/// The width of the time of day column, wide enough for "12:59 PM" on one
/// line.
const _timeWidth = 68.0;

class _HistoryTimelineState extends State<HistoryTimeline> {
  /// The entry whose choices are shown, if any.
  String? _open;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: widget.entries,
    builder: (context, entries, _) {
      final now = DateTime.now();
      String day(int index) => listenedWhen(entries[index].at.toLocal(), now);
      final mixed =
          entries.any((entry) => entry.place is AudioPosition) &&
          entries.any((entry) => entry.place is TextPosition);
      Widget row(int index) => _row(context, entries[index], mixed: mixed);
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
          final at when at == 0 || day(at) != day(at - 1) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [_DayLabel(day(at)), row(at)],
          ),
          final at => row(at),
        },
      );
    },
  );

  /// One entry: its time of day, its mark on the rail, what happened and
  /// where. With [mixed], the mark is a glyph of the entry's medium.
  Widget _row(
    BuildContext context,
    TimelineEntry entry, {
    required bool mixed,
  }) {
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
    final bookmark = entry is BookmarkEntry;
    final words = widget.describe(entry.place);
    final label = switch (entry) {
      ActionEntry(:final event) => _label(event),
      BookmarkEntry(:final bookmark) => bookmark.title ?? 'Bookmark',
    };
    final time = MaterialLocalizations.of(context)
        .formatTimeOfDay(TimeOfDay.fromDateTime(entry.at.toLocal()));
    final markColor = bookmark || open ? accent : scheme.onSurfaceVariant;
    final mark = switch ((mixed, entry.place)) {
      (true, AudioPosition()) => Icon(
        Icons.headphones_rounded,
        size: 13,
        color: markColor,
        semanticLabel: 'Listening',
      ),
      (true, TextPosition()) => Icon(
        Icons.menu_book_rounded,
        size: 13,
        color: markColor,
        semanticLabel: 'Reading',
      ),
      _ when bookmark => Icon(Icons.bookmark_rounded, size: 13, color: accent),
      _ => Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(shape: BoxShape.circle, color: markColor),
      ),
    };
    final detail = [
      ?words.chapter,
      if (words.quote case final quote?) '“$quote”',
    ].join(' · ');
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
                    SizedBox(width: 24, child: Center(child: mark)),
                    // A glyph of the medium takes the place of the
                    // bookmark mark on the rail, so the label shows it.
                    if (mixed && bookmark)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Icon(
                          Icons.bookmark_rounded,
                          size: 14,
                          color: accent,
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
                    // A quote can be long, so the place takes at most a
                    // third of the screen's width.
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.sizeOf(context).width / 3,
                      ),
                      child: Text(
                        words.short,
                        style: small,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (open && detail.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: _timeWidth + 30, right: 4),
                child: Text(
                  detail,
                  style: small,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
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
    String place(Place place) => widget.describe(place).short;
    return switch (entry) {
      ActionEntry(:final event) => [
        if (event.changesPosition)
          choice(
            'Go back to ${place(event.before)}',
            () => widget.onGoBack(event),
          ),
        choice('Go to ${place(event.after)}', () => widget.onGoTo(entry)),
        delete,
      ],
      BookmarkEntry(:final bookmark) => [
        choice('Go to ${place(bookmark.position)}', () => widget.onGoTo(entry)),
        choice(
          bookmark.title == null ? 'Name' : 'Rename',
          () => widget.onRename(bookmark),
        ),
        delete,
      ],
    };
  }

  /// What [event] did. A move that changed the place says how far it went:
  /// a time in listening, and pages in reading. Before the reader knows
  /// both pages, a reading move says only its direction, and the verb
  /// alone where the open book cannot place it.
  String _label(HistoryEvent<Place> event) {
    final from = widget.describe(event.before).along;
    final to = widget.describe(event.after).along;
    String moved(String verb) => switch ((from, to)) {
      (
        AlongAudio(milliseconds: final from),
        AlongAudio(milliseconds: final to),
      ) =>
        '$verb ${to >= from ? 'ahead' : 'back'} ${_span((to - from).abs())}',
      (AlongText(page: final from?), AlongText(page: final to?))
          when from != to =>
        '$verb ${to > from ? 'ahead' : 'back'} ${_pages((to - from).abs())}',
      (AlongText(fraction: final from?), AlongText(fraction: final to?))
          when from != to =>
        '$verb ${to > from ? 'ahead' : 'back'}',
      _ => verb,
    };

    return switch (event.kind) {
      HistoryAction.seek => moved('Moved'),
      HistoryAction.jump => moved('Jumped'),
      HistoryAction.chapter => 'Changed chapter',
      HistoryAction.undo => 'Undid a move',
      HistoryAction.historyRestore => 'Went back in history',
      HistoryAction.bookmarkRestore => 'Went to a bookmark',
      HistoryAction.pause => 'Paused',
      HistoryAction.resume => 'Played',
      HistoryAction.interruption => 'Interrupted',
      HistoryAction.stop => 'Stopped',
      HistoryAction.completion => 'Finished',
      HistoryAction.link => 'Followed a link',
      HistoryAction.search => 'Went to a search result',
      HistoryAction.open => 'Opened',
      HistoryAction.close => 'Closed',
    };
  }

  /// A span of [milliseconds] of listening, such as "40 s" or "2 min".
  static String _span(int milliseconds) => milliseconds < 60000
      ? '${(milliseconds / 1000).round()} s'
      : duration(milliseconds);

  /// A number of pages, such as "1 page" or "12 pages".
  static String _pages(int count) => count == 1 ? '1 page' : '$count pages';
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
