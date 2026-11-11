import 'dart:convert';
import 'dart:math';

import '../catalog/model.dart';

/// The one closed set of kinds of moves, of listening and of reading. Each
/// name is the kind's stored JSON name, so a kind is never renamed.
enum HistoryAction {
  seek,
  jump,
  chapter,
  undo,
  historyRestore,
  bookmarkRestore,
  pause,
  resume,
  interruption,
  stop,
  completion,

  /// A link on the page, or Go to note.
  link,

  /// A search result.
  search,

  /// The start of a reading visit, or a book that opened at a place that
  /// another device saved.
  open,

  /// The end of a reading visit.
  close,
}

String recordId() => List.generate(
  16,
  (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
).join();

Map<String, dynamic> encodePosition(AudioPosition position) => {
  'edition': position.editionId,
  'source': position.sourceKey,
  'revision': position.revision,
  'milliseconds': position.milliseconds,
};

/// The source files of the audio [edition] with their revisions, in the
/// form that a listening resume names them. A resume with these sources
/// belongs to exactly these files.
String editionSources(Edition edition) {
  final sources = [
    for (final file in edition.files) [file.key, file.revision],
  ]..sort((left, right) => left.first.compareTo(right.first));
  return jsonEncode(sources);
}

AudioPosition decodePosition(Object? value) {
  if (value is! Map ||
      value['edition'] is! String ||
      (value['edition'] as String).isEmpty ||
      value['source'] is! String ||
      (value['source'] as String).isEmpty ||
      value['revision'] is! String ||
      (value['revision'] as String).isEmpty ||
      value['milliseconds'] is! int ||
      (value['milliseconds'] as int) < 0) {
    throw const FormatException('Invalid saved audio position');
  }
  return AudioPosition(
    editionId: value['edition'] as String,
    sourceKey: value['source'] as String,
    revision: value['revision'] as String,
    milliseconds: value['milliseconds'] as int,
  );
}

/// One move between two places of the same medium [P].
class HistoryEvent<P extends Place> {
  const HistoryEvent({
    required this.id,
    required this.at,
    required this.kind,
    required this.before,
    required this.after,
    required this.bookTitle,
    required this.editionLabel,
    this.device,
    this.counterpartOf,
    this.matchedBy,
  });
  final String id;
  final DateTime at;
  final HistoryAction kind;

  /// The place where the move began.
  final P before;

  /// The place where the move ended.
  final P after;

  /// The names of the book and of its edition at the time of the move.
  final String bookTitle;
  final String editionLabel;

  /// The name of the device that saved [after], for a book that opened at
  /// a place that another device saved, or null.
  final String? device;

  /// For a mapped move, the place of the other medium's edition whose
  /// landing the move went to, or null for any other move. A mapped move
  /// has both this and [matchedBy].
  final Place? counterpartOf;

  /// For a mapped move, how Bookfin found its landing, or null for any
  /// other move. A name that this build does not know reads as null.
  final MatchedBy? matchedBy;

  bool get changesPosition => switch (kind) {
    HistoryAction.seek ||
    HistoryAction.jump ||
    HistoryAction.chapter ||
    HistoryAction.undo ||
    HistoryAction.historyRestore ||
    HistoryAction.bookmarkRestore ||
    HistoryAction.link ||
    HistoryAction.search ||
    HistoryAction.open => true,
    _ => false,
  };

  /// Whether this action took the person from one place to another: its
  /// kind can change the place ([changesPosition]), and its two places
  /// differ. The History timeline shows such an action as a route with two
  /// ends. Played, Interrupted and Finished go from the position sample
  /// before the change to the sample that changed it, which can differ by
  /// a fraction of a second, so they never move.
  bool get moved => changesPosition && !samePlace(before, after);

  Map<String, dynamic> toJson() => {
    'id': id,
    'at': at.toUtc().toIso8601String(),
    'kind': kind.name,
    'before': encodePlace(before),
    'after': encodePlace(after),
    'bookTitle': bookTitle,
    'editionLabel': editionLabel,
    'device': ?device,
    'counterpartOf': ?switch (counterpartOf) {
      null => null,
      final place => encodePlace(place),
    },
    'matchedBy': ?matchedBy?.name,
  };

  /// The move that [value] holds, whose places [decodePlace] decodes, for
  /// example [decodePosition] for listening. Throws a [FormatException] or
  /// a [TypeError] when [value] is not a valid move.
  factory HistoryEvent.fromJson(
    Map<String, dynamic> value,
    P Function(Object? value) decodePlace,
  ) {
    final before = decodePlace(value['before']);
    final after = decodePlace(value['after']);
    final kind = HistoryAction.values
        .where((kind) => kind.name == value['kind'])
        .firstOrNull;
    if (value['id'] is! String ||
        (value['id'] as String).isEmpty ||
        kind == null ||
        (value['device'] != null && value['device'] is! String)) {
      throw const FormatException('Invalid history action');
    }
    final counterpart = value['counterpartOf'];
    return HistoryEvent(
      id: value['id'] as String,
      at: DateTime.parse(value['at'] as String),
      kind: kind,
      before: before,
      after: after,
      bookTitle: value['bookTitle'] as String,
      editionLabel: value['editionLabel'] as String,
      device: value['device'] as String?,
      counterpartOf: counterpart == null ? null : decodeAnyPlace(counterpart),
      matchedBy: MatchedBy.values
          .where((matched) => matched.name == value['matchedBy'])
          .firstOrNull,
    );
  }
}

/// How Bookfin found the landing of a mapped move: by matched chapters, an
/// estimate, which the words of a landing call "about" (docs/plans/
/// cross-edition-places.md, design A). Each name is stored in JSON.
enum MatchedBy { chapters }

/// Where the saved place of an edition came from, as the record store's
/// journal says: [own], the last place that this installation saved there,
/// whether another installation saved the current place ([elsewhere]), and
/// the name of its [device]. [own] has the medium of the edition.
typedef PlaceOrigin = ({Place? own, bool elsewhere, String? device});

/// Where the open of an edition at [opened] moves from: this installation's
/// own last place there, when another device saved [opened], as [origin]
/// says. Null when [origin] is null or knows no own place of medium [P],
/// when the two places are the same, and when [history] already holds that
/// move, so that a second open at the same place records no second move.
P? openedFrom<P extends Place>(
  PlaceOrigin? origin,
  P opened,
  Iterable<HistoryEvent<P>> history,
) {
  final own = origin?.own;
  if (own is! P || !origin!.elsewhere || samePlace(own, opened)) return null;
  final recorded = history.any(
    (event) =>
        event.kind == HistoryAction.open &&
        samePlace(event.before, own) &&
        samePlace(event.after, opened),
  );
  return recorded ? null : own;
}

/// Whether [a] and [b] are the same place of the same source file.
bool samePlace(Place a, Place b) => switch ((a, b)) {
  (final AudioPosition a, final AudioPosition b) =>
    a.editionId == b.editionId &&
        a.sourceKey == b.sourceKey &&
        a.revision == b.revision &&
        a.milliseconds == b.milliseconds,
  (final TextPosition a, final TextPosition b) =>
    a.editionId == b.editionId &&
        a.sourceKey == b.sourceKey &&
        a.revision == b.revision &&
        a.anchor == b.anchor,
  _ => false,
};

/// The move of medium [P] that Undo can take back, and whether the place
/// where it began is saved on this device.
typedef UndoOffer<P extends Place> = ({HistoryEvent<P> action, bool saved});

/// A place in edition [P] that the person marked.
class Bookmark<P extends Place> {
  const Bookmark({
    required this.id,
    required this.position,
    required this.createdAt,
    this.bookTitle,
    this.editionLabel,
    this.title,
    this.note,
  });
  final String id;
  final P position;
  final DateTime createdAt;

  /// The names of the book and of its edition when the bookmark was saved.
  /// A listening bookmark always has both. A reading bookmark saved before
  /// reading history has neither.
  final String? bookTitle;
  final String? editionLabel;
  final String? title;
  final String? note;

  /// The bookmark as JSON. A bookmark without book names writes no names,
  /// so it keeps the bytes of the release that saved it.
  Map<String, dynamic> toJson() => {
    'id': id,
    'position': encodePlace(position),
    'createdAt': createdAt.toUtc().toIso8601String(),
    'bookTitle': ?bookTitle,
    'editionLabel': ?editionLabel,
    'title': title,
    'note': note,
  };

  /// The bookmark that [value] holds, whose place [decodePlace] decodes,
  /// for example [decodeTextPosition] for reading. Throws a
  /// [FormatException] when [value] is not a valid bookmark, or a listening
  /// bookmark without book names.
  factory Bookmark.fromJson(
    Map<String, dynamic> value,
    P Function(Object? value) decodePlace,
  ) {
    if (value['id'] is! String ||
        (value['id'] as String).isEmpty ||
        value['createdAt'] is! String ||
        [
          for (final name in ['bookTitle', 'editionLabel', 'title', 'note'])
            value[name],
        ].any((text) => text != null && text is! String)) {
      throw const FormatException('Invalid bookmark.');
    }
    final position = decodePlace(value['position']);
    if (position is AudioPosition &&
        (value['bookTitle'] == null || value['editionLabel'] == null)) {
      throw const FormatException('A listening bookmark must name its book.');
    }
    return Bookmark(
      id: value['id'] as String,
      position: position,
      createdAt: DateTime.parse(value['createdAt'] as String),
      bookTitle: value['bookTitle'] as String?,
      editionLabel: value['editionLabel'] as String?,
      title: value['title'] as String?,
      note: value['note'] as String?,
    );
  }
}

/// The place that [value] holds, of the medium that its keys tell:
/// `milliseconds` for a listening place, `anchor` for a reading place.
/// Throws a [FormatException] when it holds neither.
Place decodeAnyPlace(Object? value) => switch (value) {
  {'milliseconds': _} => decodePosition(value),
  {'anchor': _} => decodeTextPosition(value),
  _ => throw const FormatException('Invalid saved place.'),
};

/// The JSON of [place], as its medium writes it.
Map<String, dynamic> encodePlace(Place place) => switch (place) {
  AudioPosition() => encodePosition(place),
  TextPosition() => encodeTextPosition(place),
};

Map<String, dynamic> encodeTextPosition(TextPosition position) => {
  'edition': position.editionId,
  'source': position.sourceKey,
  'revision': position.revision,
  'anchor': position.anchor,
};

TextPosition decodeTextPosition(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Invalid saved reading position.');
  }
  for (final name in ['edition', 'source', 'revision', 'anchor']) {
    if (value[name] is! String || (value[name] as String).isEmpty) {
      throw const FormatException('Invalid saved reading position.');
    }
  }
  return TextPosition(
    editionId: value['edition'] as String,
    sourceKey: value['source'] as String,
    revision: value['revision'] as String,
    anchor: value['anchor'] as String,
  );
}

/// One moment of a book's timeline: a move or a bookmark.
sealed class TimelineEntry {
  const TimelineEntry();
  String get id;
  DateTime get at;

  /// The name of the book at the time of the entry, or null for a reading
  /// bookmark saved before reading history.
  String? get bookTitle;

  /// The place of the entry: where a move ended, or the bookmark's place.
  Place get place;
}

final class ActionEntry extends TimelineEntry {
  const ActionEntry(this.event);
  final HistoryEvent<Place> event;
  @override
  String get id => event.id;
  @override
  DateTime get at => event.at;
  @override
  String get bookTitle => event.bookTitle;
  @override
  Place get place => event.after;
}

final class BookmarkEntry extends TimelineEntry {
  const BookmarkEntry(this.bookmark);
  final Bookmark<Place> bookmark;
  @override
  String get id => bookmark.id;
  @override
  DateTime get at => bookmark.createdAt;
  @override
  String? get bookTitle => bookmark.bookTitle;
  @override
  Place get place => bookmark.position;
}

/// A place in words. [short] names it in a timeline row, such as "p. 134",
/// "37%" or "01:02:15". [chapter] and [quote] describe it on the tile of an
/// open timeline entry, when they are known. [quote] is null when [short]
/// already shows the whole quote. [along] says how
/// far into its edition the place is, so that a move can say how far it
/// went, or null when that is unknown.
typedef PlaceWords = ({
  String short,
  String? chapter,
  String? quote,
  Along? along,
});

/// How far into its edition a place is. Only two places of the same
/// medium compare.
sealed class Along {
  const Along();
}

/// A time in an audio edition, in milliseconds from the edition's start.
/// It is the time that [PlaceWords.short] shows through `audioTime`, so a
/// distance between the `audioSeconds` of two places agrees with their
/// place texts.
final class AlongAudio extends Along {
  const AlongAudio(this.milliseconds);
  final int milliseconds;
}

/// A place in a text edition: the number of its page among the book's
/// pages, from 1, and its share of the book, from 0 at the start to 1 at
/// the end. Either can be unknown, but not both.
final class AlongText extends Along {
  const AlongText({this.page, this.fraction})
    : assert(page != null || fraction != null);
  final int? page;
  final double? fraction;
}
