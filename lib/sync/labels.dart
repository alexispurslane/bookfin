import 'dart:convert';

import '../catalog/model.dart';
import '../foundation/time.dart' show audioTime, duration, listenedWhen;
import '../playback/audio_outline.dart';
import 'journal.dart';

/// What a choice between the saved versions of one record says.
final class ConflictLabels {
  const ConflictLabels({
    required this.title,
    required this.kind,
    required this.book,
    required this.choices,
    required this.track,
  });

  /// The name of the book, once: its title in the current library, or else
  /// the title that a version saved, marked as outside the library.
  final String title;

  /// The kind of record, for example "Listening saved place" or "Reading
  /// bookmark".
  final String kind;

  /// The book in the current library, or null when the library lacks it.
  final Book? book;

  /// One label for each saved version, in the order of the versions.
  final List<ChoiceLabel> choices;

  /// Where the versions lie in the whole book, or null when one of them has
  /// no place there: a bookmark, a history entry, a deletion, a reading
  /// place, or a listening place in an edition that the library lacks.
  final ConflictTrack? track;

  /// Whether the versions are saved places, which stay as bookmarks after
  /// the choice.
  bool get places => kind.endsWith('saved place');
}

/// The whole book as one track, from its start to its end.
final class ConflictTrack {
  const ConflictTrack({
    required this.places,
    required this.chapters,
    required this.length,
  });

  /// Where the place of each choice lies, from 0 at the start to 1 at the
  /// end, in the order of the choices.
  final List<double> places;

  /// Where each chapter after the first begins, from 0 to 1, in order.
  final List<double> chapters;

  /// The length of the book, for example "10 h 12 m".
  final String length;
}

/// The conflicts of [conflicts] whose records belong to an edition of
/// [book], in their order.
Map<String, List<Map<String, dynamic>>> bookConflicts(
  Map<String, List<Map<String, dynamic>>> conflicts,
  Book book,
) => {
  for (final entry in conflicts.entries)
    if (entry.value.any(
      (version) => switch (version['value']) {
        final Map<String, dynamic> value => book.editions.any(
          (edition) => edition.id == _position(value)['edition'],
        ),
        _ => false,
      },
    ))
      entry.key: entry.value,
};

/// What the Settings row says while choices wait in [conflicts], for
/// example "A choice waits · First Frost", or null while none waits. [books]
/// is the current library, which names the books.
String? waitingChoices(
  Map<String, List<Map<String, dynamic>>> conflicts,
  List<Book> books,
) {
  if (conflicts.isEmpty) return null;
  final titles = {
    for (final MapEntry(key: record, value: versions) in conflicts.entries)
      _title(record, versions, books),
  }.join(', ');
  return conflicts.length == 1
      ? 'A choice waits · $titles'
      : '${conflicts.length} choices wait · $titles';
}

/// What the choice of one saved version says.
final class ChoiceLabel {
  const ChoiceLabel({
    required this.identity,
    required this.source,
    required this.time,
    required this.detail,
    required this.bookmarkTitle,
  });

  /// The identity of the saved version's sync action.
  final String identity;

  /// Where the version comes from: the name of the device that saved it,
  /// for example "Pixel 8", or else when it was saved, for example "Saved
  /// 9:12 PM yesterday".
  final String source;

  /// The time of a listening place, for example "2:33:16", or null for a
  /// version without one: a reading place or a deletion.
  final String? time;

  /// What the version holds besides [time]: the chapter, the page and quote
  /// of a reading place, and the title and note of a bookmark. A deletion
  /// says "Keep deletion".
  final String detail;

  /// The title of the bookmark that keeps this place when the user chooses
  /// another one: [source] and the chapter.
  final String bookmarkTitle;

  /// What the version holds: [time], then [detail].
  String get place => [?time, if (detail.isNotEmpty) detail].join(' · ');

  /// The label as one line: [source], then [place].
  String get text => '$source · $place';
}

/// The labels of the saved versions [versions] of [record], which are sync
/// actions as `RecordJournal.conflicts` holds them. [books] is the current
/// library, which names the book and the chapters. [now] is the current
/// local time, and [clock] writes the local time of day of a moment in the
/// app's locale, for example "9:12 PM".
ConflictLabels labelConflict(
  String record,
  List<Map<String, dynamic>> versions, {
  required List<Book> books,
  required DateTime now,
  required String Function(DateTime at) clock,
}) {
  final address = jsonDecode(record) as List;
  final values = [
    for (final version in versions) version['value'] as Map<String, dynamic>?,
  ];
  final names = [for (final version in versions) _deviceName(version)];
  final sources = [
    for (final (index, version) in versions.indexed)
      _source(
        names[index],
        _savedAt(version, values[index]),
        // A second device of the same name also says when it saved.
        named: names.where((name) => name == names[index]).length == 1,
        now: now,
        clock: clock,
      ),
  ];
  final chapters = [
    for (final value in values) value == null ? null : _chapter(books, value),
  ];
  final kind = switch (address[1]) {
    'bookmarks' => 'bookmark',
    'history' => 'history entry',
    _ => 'saved place',
  };
  final value = values.nonNulls.firstOrNull;
  return ConflictLabels(
    title: _title(record, versions, books),
    kind: '${address.first == 'audio' ? 'Listening' : 'Reading'} $kind',
    book: value == null ? null : _book(books, value),
    choices: [
      for (final (index, version) in versions.indexed)
        ChoiceLabel(
          identity: RecordJournal.identity(version),
          source: sources[index],
          time: _time(values[index]),
          detail: _detail(values[index], chapters[index]),
          bookmarkTitle: [sources[index], ?chapters[index]].join(' · '),
        ),
    ],
    track: address[1] == 'resumes' ? _track(books, values) : null,
  );
}

/// The name of the book of the versions [versions] of [record].
String _title(
  String record,
  List<Map<String, dynamic>> versions,
  List<Book> books,
) => switch (versions
    .map((version) => version['value'])
    .whereType<Map<String, dynamic>>()
    .firstOrNull) {
  null => 'Book unavailable',
  final value => _bookName(books, value),
};

/// The track of the listening places [values] in their edition of [books],
/// or null when one of them is no listening place in a known file of it.
ConflictTrack? _track(List<Book> books, List<Map<String, dynamic>?> values) {
  final first = values.firstOrNull;
  final edition = first == null ? null : _edition(books, first);
  if (edition == null) return null;
  final outline = audioOutline(edition);
  final total = outline.length;
  if (total == null || total <= 0) return null;
  final places = <int>[];
  for (final value in values) {
    if (value == null || value['edition'] != edition.id) return null;
    final milliseconds = value['milliseconds'];
    final known = edition.files.any(
      (file) =>
          file.key == value['source'] && file.revision == value['revision'],
    );
    final offset = known ? outline.fileStarts[value['source']] : null;
    if (offset == null || milliseconds is! int) return null;
    places.add(offset + milliseconds);
  }
  return ConflictTrack(
    places: [for (final place in places) (place / total).clamp(0.0, 1.0)],
    chapters: [
      for (final chapter in outline.chapters)
        if (chapter.editionMilliseconds! > 0)
          chapter.editionMilliseconds! / total,
    ],
    length: duration(total),
  );
}

/// The name of the device that saved [version], or null when the version
/// does not name one, as versions from before device names do not.
String? _deviceName(Map<String, dynamic> version) =>
    switch (version['device']) {
      final String name when name.trim().isNotEmpty => name.trim(),
      _ => null,
    };

/// When [version] was saved, or else when its [value] says it was made, or
/// null when neither says.
DateTime? _savedAt(Map<String, dynamic> version, Map<String, dynamic>? value) {
  for (final at in [version['savedAt'], value?['createdAt'], value?['at']]) {
    if (at is String) {
      if (DateTime.tryParse(at) case final parsed?) return parsed;
    }
  }
  return null;
}

/// The source of a version: the device [name] alone when it is [named] by
/// it alone, the name and the time [at] when another version has the same
/// name, and the time alone when there is no name.
String _source(
  String? name,
  DateTime? at, {
  required bool named,
  required DateTime now,
  required String Function(DateTime at) clock,
}) {
  if (name != null && (named || at == null)) return name;
  if (at == null) return 'Unknown device';
  final day = listenedWhen(at, now);
  final when = switch (day) {
    'Today' || 'Yesterday' => '${clock(at)} ${day.toLowerCase()}',
    _ => '${clock(at)} on $day',
  };
  return name == null ? 'Saved $when' : '$name, saved $when';
}

/// The place of a resume, a bookmark, or a history entry [value].
Map<String, dynamic> _position(Map<String, dynamic> value) =>
    (value['position'] ?? value['after'] ?? value) as Map<String, dynamic>;

/// The name of the chapter that holds the place of [value]: the audio
/// chapter of the current library, or the source page of a reading place.
/// Null when the library lacks the source file or the place has no page.
String? _chapter(List<Book> books, Map<String, dynamic> value) {
  final position = _position(value);
  final milliseconds = position['milliseconds'];
  if (milliseconds is int) {
    return _edition(books, position)?.files
        .where(
          (file) =>
              file.key == position['source'] &&
              file.revision == position['revision'],
        )
        .firstOrNull
        ?.chapterAt(milliseconds);
  }
  final page = _readingAddress(position)?['page'];
  return page is int ? 'Source page $page' : null;
}

/// The time of the listening place of [value], or null when it has none.
String? _time(Map<String, dynamic>? value) =>
    switch (value == null ? null : _position(value)['milliseconds']) {
      final int milliseconds => audioTime(milliseconds),
      _ => null,
    };

/// What [value] holds besides its time: its [chapter], or its reading
/// place, and the title and note of a bookmark.
String _detail(Map<String, dynamic>? value, String? chapter) {
  if (value == null) return 'Keep deletion';
  final position = _position(value);
  final parts = <String>[];
  if (position['milliseconds'] is int) {
    if (chapter != null) parts.add(chapter);
  } else if (position['anchor'] is String) {
    if (chapter != null) parts.add(chapter);
    final quote = _readingAddress(position)?['quote'];
    parts.add(
      quote is String && quote.trim().isNotEmpty
          ? '“$quote”'
          : 'Saved reading place (preview unavailable)',
    );
  }
  for (final name in ['title', 'note']) {
    if (value[name] is String && (value[name] as String).isNotEmpty) {
      parts.add(value[name] as String);
    }
  }
  return parts.join(' · ');
}

/// The decoded anchor of a reading [position], or null when it is not an
/// object.
Map<String, dynamic>? _readingAddress(Map<String, dynamic> position) {
  final anchor = position['anchor'];
  if (anchor is! String) return null;
  try {
    final decoded = jsonDecode(anchor);
    return decoded is Map<String, dynamic> ? decoded : null;
  } on FormatException {
    return null;
  }
}

Edition? _edition(List<Book> books, Map<String, dynamic> position) => books
    .expand((book) => book.editions)
    .where((edition) => edition.id == position['edition'])
    .firstOrNull;

/// The book of [value] in the current library, or null.
Book? _book(List<Book> books, Map<String, dynamic> value) {
  final position = _position(value);
  return books
      .where(
        (book) =>
            book.editions.any((edition) => edition.id == position['edition']),
      )
      .firstOrNull;
}

/// The title of the book of [value] in the current library, or else the
/// title that [value] saved, marked as outside the library.
String _bookName(List<Book> books, Map<String, dynamic> value) =>
    _book(books, value)?.title ??
    (value['bookTitle'] is String
        ? '${value['bookTitle']} (not in the current library)'
        : 'Book not in the current library');
