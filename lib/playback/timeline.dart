import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

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
                // the edition of any other place there, as a move with Undo.
                if (showing != EditionKind.text) reading!.show(context);
                unawaited(restore());
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
            onGoBefore: (event) => go(
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

/// A dense, vertical timeline of listening and reading, grouped by day.
/// Each move is a route with two ends: its row names the place where it
/// went, after an arrow, and a tap opens the route as two tiles of one
/// size, Before on the left and After on the right. An entry that did not
/// move, and a bookmark, open as one tile with their one place. A tap on a
/// tile goes to its place. An open row keeps the shape of a closed one, and
/// only its highlight shows that it is open. A bookmark offers Name or
/// Rename beside its tile. A swipe of a row toward its start, or the row's
/// Delete action for a screen reader, offers Delete. When the
/// entries hold both media, a glyph on the rail marks the medium of each
/// entry. The timeline changes no records itself: it reports each choice
/// through its callbacks.
class HistoryTimeline extends StatefulWidget {
  const HistoryTimeline({
    super.key,
    required this.entries,
    required this.describe,
    this.showBooks = false,
    this.header,
    this.scroll,
    required this.onGoBefore,
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

  /// Reports a tap on the Before end of a move: return to
  /// [HistoryEvent.before], where the move began.
  final ValueChanged<HistoryEvent<Place>> onGoBefore;

  /// Reports a tap on the After end of a move, or on the one place of an
  /// entry that did not move: return to [TimelineEntry.place], where an
  /// action ended or where a bookmark is.
  final ValueChanged<TimelineEntry> onGoTo;

  /// Reports Name or Rename on a bookmark.
  final ValueChanged<Bookmark<Place>> onRename;

  /// Reports Delete on an entry. The listener has not confirmed it yet,
  /// so the row stays until the entry leaves [entries].
  final ValueChanged<TimelineEntry> onDelete;

  @override
  State<HistoryTimeline> createState() => _HistoryTimelineState();
}

/// The width of the time of day column, wide enough for "12:59 PM" on one
/// line.
const _timeWidth = 68.0;

const _rowRadius = BorderRadius.all(Radius.circular(8));

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
  /// where. A move names the place where it went after an arrow. With
  /// [mixed], the mark is a glyph of the entry's medium. An open entry
  /// shows its route under the row. A swipe of the row toward its start
  /// reports Delete.
  Widget _row(
    BuildContext context,
    TimelineEntry entry, {
    required bool mixed,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final night = theme.brightness == Brightness.dark;
    final accent = glowAccent(theme);
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
    final row = Ink(
      decoration: BoxDecoration(
        color: open
            ? (night
                  ? scheme.onSurface.withValues(alpha: 0.06)
                  : scheme.surface.withValues(alpha: 0.55))
            : null,
        borderRadius: _rowRadius,
      ),
      child: InkWell(
        borderRadius: _rowRadius,
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
              // A glyph of the medium takes the place of the bookmark mark
              // on the rail, so the label shows it.
              if (mixed && bookmark)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(Icons.bookmark_rounded, size: 14, color: accent),
                ),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    text: label,
                    children: [
                      if (widget.showBooks)
                        TextSpan(text: ' · ${entry.bookTitle}', style: small),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14),
                ),
              ),
              const SizedBox(width: 8),
              // A quote can be long, so the place takes at most a third of
              // the screen's width.
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width / 3,
                ),
                child: Text(
                  _moveOf(entry) == null ? words.short : '→ ${words.short}',
                  style: small,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Stack(
          children: [
            // The rail that joins the entries of a day. It runs beside the
            // rows, not through the tiles of an open route.
            Positioned(
              left: _timeWidth + 11.25,
              top: 0,
              bottom: 0,
              child: Container(width: 1.5, color: scheme.outlineVariant),
            ),
            // A swiped row slides within its own bounds, not over the
            // sheet's edge.
            ClipRRect(
              borderRadius: _rowRadius,
              child: Dismissible(
                key: ValueKey(entry.id),
                direction: DismissDirection.endToStart,
                background: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.error,
                    borderRadius: _rowRadius,
                  ),
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Icon(
                        Icons.delete_outline,
                        size: 20,
                        color: scheme.onError,
                      ),
                    ),
                  ),
                ),
                // The listener confirms a delete, and the entry leaves when
                // its records change, so the row always springs back.
                confirmDismiss: (_) async {
                  widget.onDelete(entry);
                  return false;
                },
                child: Semantics(
                  customSemanticsActions: {
                    const CustomSemanticsAction(label: 'Delete'): () =>
                        widget.onDelete(entry),
                  },
                  child: row,
                ),
              ),
            ),
          ],
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 8),
            child: _route(entry),
          ),
      ],
    );
  }

  /// The places of an open [entry], as tiles across its row: Before and
  /// After for a move, in the order that they happened, and the one place
  /// of an entry that did not move. A bookmark's Name or Rename sits at the
  /// end of its tile's line, as tall as the tile.
  Widget _route(TimelineEntry entry) {
    final move = _moveOf(entry);
    if (move == null) {
      final place = _end('Go to', entry.place, () => widget.onGoTo(entry));
      if (entry case BookmarkEntry(:final bookmark)) {
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: place),
              const SizedBox(width: 8),
              _Tile(
                onTap: () => widget.onRename(bookmark),
                child: Tooltip(
                  message: bookmark.title == null ? 'Name' : 'Rename',
                  child: const SizedBox.square(
                    dimension: 48,
                    child: Icon(Icons.edit_outlined, size: 20),
                  ),
                ),
              ),
            ],
          ),
        );
      }
      return place;
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _end('Before', move.before, () => widget.onGoBefore(move)),
          ),
          SizedBox(
            width: 22,
            child: Center(
              child: ExcludeSemantics(
                child: Text(
                  '→',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: _end('After', move.after, () => widget.onGoTo(entry)),
          ),
        ],
      ),
    );
  }

  /// One end of a route: a tile with [role] and [place] in words, whose tap
  /// calls [go]. Every tile describes its place here, so that a later
  /// change can show a place of another edition in one spot.
  Widget _end(String role, Place place, VoidCallback go) =>
      _PlaceTile(role: role, words: widget.describe(place), onTap: go);

  /// The move of [entry] when it has two ends ([HistoryEvent.moved]). Null
  /// for a bookmark, and for an action that stayed at one place, such as a
  /// pause or the open of a reading visit.
  static HistoryEvent<Place>? _moveOf(TimelineEntry entry) => switch (entry) {
    ActionEntry(:final event) when event.moved => event,
    _ => null,
  };

  /// What [event] did. A move that changed the place says how far it went:
  /// a time in listening, and pages in reading. Before the reader knows
  /// both pages, a reading move says only its direction, and the verb
  /// alone where the open book cannot place it.
  String _label(HistoryEvent<Place> event) {
    final from = widget.describe(event.before).along;
    final to = widget.describe(event.after).along;
    String moved(String verb) => switch ((from, to)) {
      // The distance between the two shown times, so that it agrees with
      // them.
      (
        AlongAudio(milliseconds: final from),
        AlongAudio(milliseconds: final to),
      ) =>
        _listeningMove(verb, audioSeconds(from), audioSeconds(to)),
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
      HistoryAction.open => switch (event.device) {
        final device? => 'Opened at the place from $device',
        null => 'Opened',
      },
      HistoryAction.close => 'Closed',
    };
  }

  /// A listening move from the shown second [from] to the shown second
  /// [to], such as "Moved back 40 s" or "Jumped ahead 1 m 31 s". A move
  /// within one shown second reads as [verb] alone, because its two place
  /// texts are the same.
  static String _listeningMove(String verb, int from, int to) => from == to
      ? verb
      : '$verb ${to > from ? 'ahead' : 'back'} ${_span((to - from).abs())}';

  /// A span of [seconds] above zero, such as "40 s", "1 m 31 s", "2 m" or
  /// "1 h 0 m 5 s": every unit from the largest one that is not zero down
  /// to the smallest one that is not zero.
  static String _span(int seconds) {
    assert(seconds > 0);
    final units = [
      (seconds ~/ 3600, 'h'),
      (seconds ~/ 60 % 60, 'm'),
      (seconds % 60, 's'),
    ];
    final first = units.indexWhere((unit) => unit.$1 > 0);
    final last = units.lastIndexWhere((unit) => unit.$1 > 0);
    return [
      for (final (count, unit) in units.sublist(first, last + 1))
        '$count $unit',
    ].join(' ');
  }

  /// A number of pages, such as "1 page" or "12 pages".
  static String _pages(int count) => count == 1 ? '1 page' : '$count pages';
}

/// One place of an open timeline entry, as a tile that goes there on a
/// tap: its [role], such as Before, its place text, and its chapter and
/// quote when [words] knows them. Each line stays on one line, and a line
/// that is too long ends in "…".
class _PlaceTile extends StatelessWidget {
  const _PlaceTile({
    required this.role,
    required this.words,
    required this.onTap,
  });
  final String role;
  final PlaceWords words;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final detail = [
      ?words.chapter,
      if (words.quote case final quote?) '“$quote”',
    ].join(' · ');
    Widget line(String text, TextStyle style, {String? semanticsLabel}) => Text(
      text,
      style: style,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      semanticsLabel: semanticsLabel,
    );
    return _Tile(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            line(
              role.toUpperCase(),
              TextStyle(
                fontSize: 10,
                letterSpacing: 0.6,
                color: scheme.onSurfaceVariant,
              ),
              semanticsLabel: role,
            ),
            line(
              words.short,
              TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: glowAccent(theme),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            if (detail.isNotEmpty)
              line(
                detail,
                TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }
}

/// A button of an open timeline entry, as a tile with a thin outline that
/// shows [child] and calls [onTap].
class _Tile extends StatelessWidget {
  const _Tile({required this.onTap, required this.child});
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final night = theme.brightness == Brightness.dark;
    return MergeSemantics(
      child: Semantics(
        button: true,
        child: Material(
          color: night
              ? scheme.onSurface.withValues(alpha: 0.07)
              : scheme.surface.withValues(alpha: 0.75),
          shape: RoundedRectangleBorder(
            borderRadius: const BorderRadius.all(Radius.circular(14)),
            side: BorderSide(color: scheme.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(onTap: onTap, child: child),
        ),
      ),
    );
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
