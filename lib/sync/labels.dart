import 'dart:convert';

import '../catalog/model.dart';
import '../foundation/time.dart' show audioTime, listenedWhen;
import 'journal.dart';

/// What a choice between the saved versions of one record says: [heading]
/// names the book once and the kind of record, and [choices] holds one label
/// for each saved version, in the order of the versions.
typedef ConflictLabels = ({String heading, List<ChoiceLabel> choices});

/// What the choice of one saved version says.
final class ChoiceLabel {
  const ChoiceLabel({
    required this.identity,
    required this.source,
    required this.place,
    required this.bookmarkTitle,
  });

  /// The identity of the saved version's sync action.
  final String identity;

  /// Where the version comes from: the name of the device that saved it,
  /// for example "Pixel 8", or else when it was saved, for example "Saved
  /// 9:12 PM yesterday".
  final String source;

  /// What the version holds: a listening place as its time and chapter, for
  /// example "2:33:16 · Chapter 7", a reading place as its page and quote,
  /// and the title and note of a bookmark.
  final String place;

  /// The title of the bookmark that keeps this place when the user chooses
  /// another one: [source] and the chapter.
  final String bookmarkTitle;

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
  final book = values.nonNulls.firstOrNull;
  return (
    heading:
        '${book == null ? 'Book unavailable' : _bookName(books, book)} · '
        '${address.first == 'audio' ? 'Listening' : 'Reading'} $kind · '
        'choose a saved version',
    choices: [
      for (final (index, version) in versions.indexed)
        ChoiceLabel(
          identity: RecordJournal.identity(version),
          source: sources[index],
          place: _place(values[index], chapters[index]),
          bookmarkTitle: [sources[index], ?chapters[index]].join(' · '),
        ),
    ],
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

/// What [value] holds after its source: its time and [chapter], or its
/// reading place, and the title and note of a bookmark.
String _place(Map<String, dynamic>? value, String? chapter) {
  if (value == null) return 'Keep deletion';
  final position = _position(value);
  final parts = <String>[];
  if (position['milliseconds'] is int) {
    parts.add(audioTime(position['milliseconds'] as int));
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

/// The title of the book of [value] in the current library, or else the
/// title that [value] saved, marked as outside the library.
String _bookName(List<Book> books, Map<String, dynamic> value) {
  final position = _position(value);
  final book = books
      .where(
        (book) =>
            book.editions.any((edition) => edition.id == position['edition']),
      )
      .firstOrNull;
  return book?.title ??
      (value['bookTitle'] is String
          ? '${value['bookTitle']} (not in the current library)'
          : 'Book not in the current library');
}
