import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../catalog/glass.dart';
import '../catalog/model.dart';
import '../crossings/alignment.dart' show Refusal;
import '../crossings/crossings.dart';
import '../crossings/scope.dart';
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
// the ReaderScope for reading. It routes each choice by one rule
// (docs/plans/cross-edition-places.md, "One routing rule"): over an open
// edition, a place of the other medium of the same book goes to its
// landing in the open edition, which Crossings finds, as a move of the
// open edition's owner. Any other place goes to the owner of its own
// medium, which shows it in its own edition, and the screen of that medium
// comes to the front. It also confirms a delete, closes the sheet before a
// jump, and names a bookmark through the shared bookmark editor.

/// Opens the History of [book] on a glass sheet: the listening moves and
/// bookmarks of [playback] and, under a [ReaderScope], the reading moves
/// and bookmarks of its reader, together, newest first. Without a book, the
/// timeline shows every book and names the book of each entry.
///
/// [showing] is the medium of the screen under the sheet: audio in the
/// player, text in the reader, and null elsewhere, such as on the book
/// page. Under a [CrossingsScope], Go to on a place of the other medium of
/// the open book goes to its landing in the open edition, and the tile
/// names the landing, or says why none exists. Go to on any other place of
/// another medium shows the player or the reader at that place.
void openHistory(
  BuildContext context,
  Playback? playback, {
  Book? book,
  EditionKind? showing,
}) {
  final reading = ReaderScope.maybeOf(context);
  final reader = reading?.reader;
  final crossings = CrossingsScope.maybeOf(context);

  PlaceWords describe(Place place) => switch (place) {
    AudioPosition() => playback!.describe(place),
    TextPosition() => reader!.describe(place),
  };

  // The book and the edition under the sheet, if any. A choice that goes
  // to a place closes the sheet, so they stay while it is open.
  final (shownBook, shownEdition) = switch (showing) {
    EditionKind.audio => (playback?.book, playback?.edition),
    EditionKind.text => (reader?.book, reader?.edition),
    null => (null, null),
  };

  /// The edition of [place] and the open edition, when Go to on [place]
  /// goes to its landing in the open edition: [place] is in an edition of
  /// the other medium of the open book. Null when Go to on [place] shows it
  /// in its own edition.
  ({Edition from, Edition into})? crossingOf(Place place) {
    if (crossings == null || shownBook == null || shownEdition == null) {
      return null;
    }
    final from = shownBook.editions
        .where((edition) => edition.id == place.editionId)
        .firstOrNull;
    if (from == null || from.kind == shownEdition.kind) return null;
    return (from: from, into: shownEdition);
  }

  // The open edition's alignments with the book's editions of the other
  // medium start now, so that the tiles name their landings when they open
  // and Go to rarely waits.
  if (crossings != null && shownBook != null && shownEdition != null) {
    for (final edition in shownBook.editions) {
      if (edition.kind != shownEdition.kind) {
        crossings.prepare(from: edition, into: shownEdition);
      }
    }
  }

  /// Where Go to on [place] goes, in words: its landing in the open
  /// edition, or the place itself with the reason why it has none. Until
  /// the landing is known, the place itself, and the words fill in when
  /// Crossings notifies. While speech finds the landing, its estimate with
  /// "about", or the place itself.
  LandingWords landingOf(Place place) {
    final own = (words: describe(place), note: null);
    final pair = crossingOf(place);
    if (pair == null) return own;
    final crossing = crossings!.landingNow(
      place,
      from: pair.from,
      into: pair.into,
    );
    final Settled? shown = switch (crossing) {
      Refining(:final estimate) => estimate,
      final Settled settled => settled,
      null => null,
    };
    PlaceWords about(PlaceWords words, Landing landing) =>
        crossing is Refining || landing.matchedBy == MatchedBy.chapters
        ? _about(words)
        : words;
    return switch (shown) {
      null => own,
      final AudioLanding landing => (
        words: about(playback!.describe(landing.place), landing),
        note: null,
      ),
      final TextLanding landing => switch (reader!.describeLanding(landing)) {
        final words? => (words: about(words, landing), note: null),
        null => own,
      },
      NoLanding(:final reason) => (
        words: own.words,
        note:
            '${_why(reason)}, so this opens the ${switch (place) {
              AudioPosition() => 'audiobook',
              TextPosition() => 'ebook',
            }}.',
      ),
    };
  }

  // The tile whose Go to waits for its landing, if any. Cancel, another Go
  // to, and the close of the sheet end the wait, and then nothing moves.
  final going = ValueNotifier<GoingTo?>(null);
  var closed = false;

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
          // Shows [place] in its own edition: [restore] moves the owner of
          // its medium there, and the screen of that medium comes to the
          // front.
          void goAsBefore(Place place, Future<void> Function() restore) {
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

          // A choice that goes to a place closes the timeline, so the screen
          // that shows the place offers Undo. A place of the other medium
          // goes to its landing in the open edition, as a move of [kind].
          // Without a landing, it shows the place in its own edition. While
          // the landing is not known yet, as while speech finds it, the
          // sheet stays, [tile] shows a progress state with Cancel, and the
          // sheet closes when the landing arrives.
          void go(
            Place place,
            HistoryAction kind,
            Future<void> Function() restore,
            GoingTo tile,
          ) {
            final pair = crossingOf(place);
            if (pair == null) {
              Navigator.pop(sheet);
              return goAsBefore(place, restore);
            }
            final waits = crossings!.landingNow(
              place,
              from: pair.from,
              into: pair.into,
            ) is! Settled;
            if (waits) {
              going.value = tile;
            } else {
              Navigator.pop(sheet);
            }
            unawaited(() async {
              final Settled landing;
              try {
                landing = await crossings.landing(
                  place,
                  from: pair.from,
                  into: pair.into,
                );
              } catch (_) {
                // A bug: the wait ends, and nothing moves.
                if (going.value == tile) going.value = null;
                rethrow;
              }
              if (waits) {
                if (closed || going.value != tile) return;
                going.value = null;
                if (sheet.mounted) Navigator.pop(sheet);
              }
              final went = switch (landing) {
                final AudioLanding landing => await playback!.goToLanding(
                  landing,
                  kind,
                ),
                final TextLanding landing => await reader!.goToLanding(
                  landing,
                  kind,
                ),
                NoLanding() => false,
              };
              if (!went && context.mounted) goAsBefore(place, restore);
            }());
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
            describe: describe,
            landingOf: landingOf,
            landingChanges: crossings?.changes,
            going: going,
            onCancel: () => going.value = null,
            showBooks: book == null,
            header: RecordSaveStatus(playback: playback, reader: reader),
            scroll: scroll,
            onGoBefore: (event) => go(
              event.before,
              HistoryAction.historyRestore,
              () => switch (event.before) {
                AudioPosition() => playback!.restoreHistory(event.id),
                TextPosition() => reader!.restoreHistory(event.id),
              },
              (entryId: event.id, before: true),
            ),
            onGoTo: (entry) => switch (entry) {
              ActionEntry(:final event) => go(
                event.after,
                HistoryAction.historyRestore,
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
                (entryId: event.id, before: false),
              ),
              BookmarkEntry(:final bookmark) => go(
                bookmark.position,
                HistoryAction.bookmarkRestore,
                () => switch (bookmark.position) {
                  AudioPosition() => playback!.restoreBookmark(bookmark.id),
                  TextPosition() => reader!.restoreBookmark(bookmark.id),
                },
                (entryId: bookmark.id, before: false),
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
      // The sheet still draws while it slides away, so [going] stays usable.
      // It holds nothing once the sheet's widgets stop listening.
    ).whenComplete(() => closed = true),
  );
}

/// [words] of an estimate, such as "about p. 134".
PlaceWords _about(PlaceWords words) => (
  short: 'about ${words.short}',
  chapter: words.chapter,
  quote: words.quote,
  along: words.along,
);

/// Why a place has no landing in the open edition, for [reason].
String _why(Refusal reason) => switch (reason) {
  Refusal.noChapters => 'One of these editions has no chapters',
  Refusal.fewMatches => 'The chapters of these editions do not match',
  Refusal.partCovered => 'Too few chapters of these editions match',
  Refusal.misaligned => 'The chapters of these editions do not line up',
  Refusal.unmeasured => 'Bookfin cannot measure this place',
  Refusal.outsideMatches => 'Only one of these editions has this part',
  Refusal.noOutline => 'The ebook is not downloaded on this phone',
  Refusal.unsupportedFormat => 'Bookfin cannot match this kind of ebook',
  Refusal.unreadable => 'Bookfin cannot read the ebook\'s file',
};

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

/// Where Go to on a place goes, in words: [words] name the place that it
/// shows, and [note], when it is not null, says why Go to shows the place
/// on another screen.
typedef LandingWords = ({PlaceWords words, String? note});

/// The tile whose Go to waits: the Before end of the entry [entryId] when
/// [before], else its After end or its one place.
typedef GoingTo = ({String entryId, bool before});

/// A dense, vertical timeline of listening and reading, grouped by day.
/// Each move is a route with two ends: its row names the place where it
/// went, after an arrow, and a tap opens the route as two tiles of one
/// size, Before on the left and After on the right. An entry that did not
/// move, and a bookmark, open as one tile with their one place. A tap on a
/// tile goes to its place. An open row keeps the shape of a closed one, and
/// only its highlight shows that it is open. A bookmark offers Name or
/// Rename beside its tile. A swipe of a row toward its start, or the row's
/// Delete action for a screen reader, offers Delete. When the entries hold
/// both media, the rail has two lanes, each with its own line: listening
/// on the left and reading on the right, and a glyph of its medium marks
/// each entry in its lane. A row names its place in its own words, and a
/// tile names where Go to goes ([landingOf]). The timeline changes no
/// records itself: it reports each choice through its callbacks.
class HistoryTimeline extends StatefulWidget {
  const HistoryTimeline({
    super.key,
    required this.entries,
    required this.describe,
    this.landingOf,
    this.landingChanges,
    this.going,
    this.onCancel,
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

  /// Where Go to on a place goes, in words, when that is not the place
  /// itself in its own edition: its landing in the open edition, or the
  /// place with a note that says why Go to opens another screen. Without
  /// it, each tile names its place through [describe].
  final LandingWords Function(Place place)? landingOf;

  /// Notifies when [landingOf] can name a place in new words, such as when
  /// a landing arrives. Only the tiles of an open entry follow it.
  final Listenable? landingChanges;

  /// The tile whose Go to waits for its landing, if any. Its entry shows a
  /// progress state with Cancel, which reports [onCancel].
  final ValueListenable<GoingTo?>? going;
  final VoidCallback? onCancel;

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

/// The narrowest width of the time of day column: wide enough for "12:59
/// PM" at the normal text size. At a larger text size the column grows
/// (see `_timeColumn`).
const _timeWidth = 68.0;

/// The least space between the start of a row and its widest time of day,
/// and between its place text and its end.
const _rowInset = 6.0;

/// The space between the sides of the History's glass sheet and a row. It
/// is as small as the sheet's own gap to the screen edges, so that a row on
/// a phone 360 points wide with large text keeps room for its label.
const _listInset = 8.0;

/// The small text of a row: its time of day and its place.
const _small = TextStyle(
  fontSize: 12,
  fontFeatures: [FontFeature.tabularFigures()],
);

/// The width of the rail's one lane, and of each lane of a timeline of
/// both media, whose two lanes leave the row's label more room.
const _laneWidth = 24.0;
const _narrowLaneWidth = 16.0;

/// The size of a mark on the one lane, and of a glyph of a medium on the
/// two narrow lanes.
const _markSize = 13.0;
const _glyphSize = 12.0;

/// The width of a line of the rail.
const _lineWidth = 1.5;

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
      final column = _timeColumn(context);
      Widget row(int index) =>
          _row(context, entries[index], mixed: mixed, column: column);
      // Only the rows near the screen are built, because a history can hold
      // thousands of entries.
      return ListView.builder(
        controller: widget.scroll,
        padding: EdgeInsets.fromLTRB(
          _listInset,
          0,
          _listInset,
          16 + floatingBarInset(context),
        ),
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
  /// [mixed], the rail has a lane for each medium, and the mark is a glyph
  /// of the entry's medium in its lane. An open entry shows its route under
  /// the row. A swipe of the row toward its start reports Delete.
  Widget _row(
    BuildContext context,
    TimelineEntry entry, {
    required bool mixed,
    required ({double width, double inset}) column,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final night = theme.brightness == Brightness.dark;
    final accent = glowAccent(theme);
    final small = _small.copyWith(color: scheme.onSurfaceVariant);
    final open = _open == entry.id;
    final bookmark = entry is BookmarkEntry;
    final words = widget.describe(entry.place);
    final label = switch (entry) {
      ActionEntry(:final event) => _label(event),
      BookmarkEntry(:final bookmark) => (
        shown: bookmark.title ?? 'Bookmark',
        spoken: bookmark.title ?? 'Bookmark',
      ),
    };
    final time = timeOfDay(context, entry.at);
    final markColor = bookmark || open ? accent : scheme.onSurfaceVariant;
    final mark = switch ((mixed, entry.place)) {
      (true, AudioPosition()) => Icon(
        Icons.headphones_rounded,
        size: _glyphSize,
        color: markColor,
        semanticLabel: 'Listening',
      ),
      (true, TextPosition()) => Icon(
        Icons.menu_book_rounded,
        size: _glyphSize,
        color: markColor,
        semanticLabel: 'Reading',
      ),
      _ when bookmark => Icon(
        Icons.bookmark_rounded,
        size: _markSize,
        color: accent,
      ),
      _ => Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(shape: BoxShape.circle, color: markColor),
      ),
    };
    // Listening on the left and reading on the right.
    final (lanes, laneWidth) = mixed ? (2, _narrowLaneWidth) : (1, _laneWidth);
    final lane = mixed && entry.place is TextPosition ? 1 : 0;
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
          padding: EdgeInsetsDirectional.only(
            top: 4,
            bottom: 4,
            end: column.inset,
          ),
          child: Row(
            children: [
              SizedBox(
                width: column.width,
                child: Text(
                  time,
                  style: small,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.fade,
                  textAlign: TextAlign.right,
                ),
              ),
              for (var index = 0; index < lanes; index++)
                SizedBox(
                  width: laneWidth,
                  child: index == lane ? Center(child: mark) : null,
                ),
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
                    text: label.shown,
                    children: [
                      if (widget.showBooks)
                        TextSpan(text: ' · ${entry.bookTitle}', style: small),
                    ],
                  ),
                  semanticsLabel: [
                    label.spoken,
                    if (widget.showBooks) ?entry.bookTitle,
                  ].join(' · '),
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
            // The lines of the rail, one for each lane, which join the
            // entries of a day. They run beside the rows, not through the
            // tiles of an open route.
            for (var index = 0; index < lanes; index++)
              Positioned(
                left:
                    column.width +
                    index * laneWidth +
                    (laneWidth - _lineWidth) / 2,
                top: 0,
                bottom: 0,
                child: Container(
                  width: _lineWidth,
                  color: scheme.outlineVariant,
                ),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                switch (widget.landingChanges) {
                  null => _route(entry),
                  final changes => ListenableBuilder(
                    listenable: changes,
                    builder: (context, _) => _route(entry),
                  ),
                },
                if (widget.going case final going?)
                  ValueListenableBuilder(
                    valueListenable: going,
                    builder: (context, to, _) => to?.entryId == entry.id
                        ? _Waiting(onCancel: widget.onCancel)
                        : const SizedBox.shrink(),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  /// The time of day column at the current text size: its [width], and the
  /// [inset] before the widest time of day, such as "10:58 PM", which the
  /// column aligns to its end. The column is [_timeWidth] wide while that
  /// leaves [_rowInset] or more, and grows otherwise. A row's place text
  /// ends [inset] before the row's end, so an open row's highlight frames
  /// the time and the place alike.
  static ({double width, double inset}) _timeColumn(BuildContext context) {
    // NOTE: Engine rule 1. This lays out one short string once per build of
    // the list, far less work than a hop to another isolate.
    final painter = TextPainter(
      text: TextSpan(
        text: MaterialLocalizations.of(context).formatTimeOfDay(
          const TimeOfDay(hour: 22, minute: 58),
          alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
        ),
        style: DefaultTextStyle.of(context).style.merge(_small),
      ),
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: Directionality.of(context),
      maxLines: 1,
    )..layout();
    final widest = painter.width;
    painter.dispose();
    final inset = math.max(_rowInset, _timeWidth - widest);
    return (width: widest + inset, inset: inset);
  }

  /// The places of an open [entry], as tiles across its row: Before and
  /// After for a move, in the order that they happened, and the one place
  /// of an entry that did not move. A bookmark's Name or Rename sits at the
  /// end of its tile's line, as tall as the tile. The two ends of a move
  /// are in one edition, so they often share one note: it then shows once,
  /// under both tiles.
  Widget _route(TimelineEntry entry) {
    final move = _moveOf(entry);
    if (move == null) {
      final place = _end(
        'Go to',
        _goesTo(entry.place),
        () => widget.onGoTo(entry),
      );
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
    final (before, after) = (_goesTo(move.before), _goesTo(move.after));
    final shared = before.note != null && before.note == after.note
        ? before.note
        : null;
    final tiles = IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _end(
              'Before',
              before,
              () => widget.onGoBefore(move),
              noteShown: shared == null,
            ),
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
            child: _end(
              'After',
              after,
              () => widget.onGoTo(entry),
              noteShown: shared == null,
            ),
          ),
        ],
      ),
    );
    if (shared == null) return tiles;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        tiles,
        // Each tile reads the note to a screen reader.
        ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
            child: _Note(shared),
          ),
        ),
      ],
    );
  }

  /// Where Go to on [place] goes, in words. Every tile describes its place
  /// here.
  LandingWords _goesTo(Place place) =>
      widget.landingOf?.call(place) ??
      (words: widget.describe(place), note: null);

  /// One end of a route: a tile with [role] and where Go to goes, [goes],
  /// whose tap calls [go]. Its note shows on the tile when [noteShown], and
  /// a screen reader reads it either way.
  Widget _end(
    String role,
    LandingWords goes,
    VoidCallback go, {
    bool noteShown = true,
  }) => _PlaceTile(
    role: role,
    words: goes.words,
    note: goes.note,
    noteShown: noteShown,
    onTap: go,
  );

  /// The move of [entry] when it has two ends ([HistoryEvent.moved]). Null
  /// for a bookmark, and for an action that stayed at one place, such as a
  /// pause or the open of a reading visit.
  static HistoryEvent<Place>? _moveOf(TimelineEntry entry) => switch (entry) {
    ActionEntry(:final event) when event.moved => event,
    _ => null,
  };

  /// What [event] did, in words: `shown` on its row, as short as it can
  /// be, and `spoken` in full for a screen reader.
  ///
  /// A move that changed the place says how far it went: a time in
  /// listening, and pages in reading, such as "Ahead 40 s" or "Back 12
  /// pages". Before the reader knows both pages, a reading move says only
  /// its verb and direction, and the verb alone where the open book cannot
  /// place it. A move that went to a place that something else gave says
  /// "From" and that source, such as "From History", "From search" or
  /// "From Pixel 8". A mapped move, which went to the landing of a place of
  /// the other medium, names that medium: "From audiobook". Its spoken
  /// label says "about" when matched chapters found the landing. "Back"
  /// names only a direction in the book (docs/plans/history-choice.md).
  ({String shown, String spoken}) _label(HistoryEvent<Place> event) {
    final other = event.counterpartOf;
    final about = event.matchedBy == MatchedBy.chapters ? 'about ' : '';
    final from = widget.describe(event.before).along;
    final to = widget.describe(event.after).along;
    // Which way a move went, and how far when that is known. A listening
    // move subtracts the two shown times, so that it agrees with them.
    final step = switch ((from, to)) {
      (AlongAudio(milliseconds: final from), AlongAudio(milliseconds: final to))
          when audioSeconds(from) != audioSeconds(to) =>
        (
          ahead: audioSeconds(to) > audioSeconds(from),
          amount: _span((audioSeconds(to) - audioSeconds(from)).abs()),
        ),
      (AlongText(page: final from?), AlongText(page: final to?))
          when from != to =>
        (ahead: to > from, amount: _pages((to - from).abs())),
      (AlongText(fraction: final from?), AlongText(fraction: final to?))
          when from != to =>
        (ahead: to > from, amount: null),
      _ => null,
    };
    ({String shown, String spoken}) moved(String verb) => switch (step) {
      null => (shown: verb, spoken: verb),
      (:final ahead, amount: null) => (
        shown: '$verb ${ahead ? 'ahead' : 'back'}',
        spoken: '$verb ${ahead ? 'ahead' : 'back'}',
      ),
      (:final ahead, :final amount?) => (
        shown: '${ahead ? 'Ahead' : 'Back'} $amount',
        spoken: '$verb ${ahead ? 'ahead' : 'back'} $amount',
      ),
    };
    ({String shown, String spoken}) same(String words) =>
        (shown: words, spoken: words);

    return switch (event.kind) {
      HistoryAction.seek => moved('Moved'),
      HistoryAction.jump => moved('Jumped'),
      HistoryAction.chapter => same('Changed chapter'),
      HistoryAction.undo => same('Undid a move'),
      HistoryAction.historyRestore => switch (other) {
        null => (shown: 'From History', spoken: 'Went to a place from History'),
        AudioPosition() => (
          shown: 'From audiobook',
          spoken: 'Went to ${about}where you listened in the audiobook',
        ),
        TextPosition() => (
          shown: 'From ebook',
          spoken: 'Went to ${about}where you read in the ebook',
        ),
      },
      // Every bookmark jump shows the same short label, so that it fits a
      // narrow phone. The tiles and the spoken words name the edition.
      HistoryAction.bookmarkRestore => switch (other) {
        null => (shown: 'From bookmark', spoken: 'Went to a bookmark'),
        AudioPosition() => (
          shown: 'From bookmark',
          spoken: 'Went to ${about}a bookmark in the audiobook',
        ),
        TextPosition() => (
          shown: 'From bookmark',
          spoken: 'Went to ${about}a bookmark in the ebook',
        ),
      },
      HistoryAction.pause => same('Paused'),
      HistoryAction.resume => same('Played'),
      HistoryAction.interruption => same('Interrupted'),
      HistoryAction.stop => same('Stopped'),
      HistoryAction.completion => same('Finished'),
      HistoryAction.link => (shown: 'From link', spoken: 'Followed a link'),
      HistoryAction.search => (
        shown: 'From search',
        spoken: 'Went to a search result',
      ),
      HistoryAction.open => switch (event.device) {
        final device? => (
          shown: 'From $device',
          spoken: 'Opened at the place from $device',
        ),
        null => same('Opened'),
      },
      HistoryAction.close => same('Closed'),
    };
  }

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
/// tap: its [role], such as Before, its place text, its chapter and quote
/// when [words] knows them, and the [note] that says why Go to opens
/// another screen, when it does. Each line but the note stays on one line,
/// and a line that is too long ends in "…". The note wraps, so that it
/// reads in full before the tap. When the note shows elsewhere, as under
/// both tiles of a move, [noteShown] is false and the tile only reads it
/// to a screen reader.
class _PlaceTile extends StatelessWidget {
  const _PlaceTile({
    required this.role,
    required this.words,
    required this.note,
    required this.noteShown,
    required this.onTap,
  });
  final String role;
  final PlaceWords words;
  final String? note;
  final bool noteShown;
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
            if (note case final note? when noteShown)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: _Note(note),
              ),
            if (note case final note? when !noteShown)
              Semantics(hint: note, child: const SizedBox.shrink()),
          ],
        ),
      ),
    );
  }
}

/// The progress state of a Go to that waits for its landing, such as while
/// speech finds the sentence, with Cancel, which reports [onCancel].
class _Waiting extends StatelessWidget {
  const _Waiting({required this.onCancel});
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 10, top: 4),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: glowAccent(theme),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Text(
                'Finding the sentence…',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          TextButton(onPressed: onCancel, child: const Text('Cancel')),
        ],
      ),
    );
  }
}

/// Why Go to on a place opens another screen, in full, on as many lines as
/// it needs.
class _Note extends StatelessWidget {
  const _Note(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: 11,
      fontStyle: FontStyle.italic,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
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
