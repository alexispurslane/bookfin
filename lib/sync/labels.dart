import '../catalog/model.dart';
import '../foundation/time.dart' show audioTime, duration, listenedWhen;
import '../playback/audio_outline.dart';
import '../playback/record_codec.dart';
import '../playback/records.dart';
import 'record_address.dart';

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
RecordConflicts bookConflicts(RecordConflicts conflicts, Book book) => {
  for (final entry in conflicts.entries)
    if (entry.value.any(
      (version) => book.editions.any(
        (edition) => edition.id == version.value?.position.editionId,
      ),
    ))
      entry.key: entry.value,
};

/// What the Settings row says while choices wait in [conflicts], for
/// example "A choice waits · First Frost", or null while none waits. [books]
/// is the current library, which names the books.
String? waitingChoices(RecordConflicts conflicts, List<Book> books) {
  if (conflicts.isEmpty) return null;
  final titles = {
    for (final versions in conflicts.values) _title(versions, books),
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

/// The labels of typed [versions] of [record], derived from the journal.
/// [books] is the current
/// library, which names the book and the chapters. [now] is the current
/// local time, and [clock] writes the local time of day of a moment in the
/// app's locale, for example "9:12 PM".
ConflictLabels labelConflict(
  RecordAddress record,
  List<ConflictVersion> versions, {
  required List<Book> books,
  required DateTime now,
  required String Function(DateTime at) clock,
}) {
  final values = [for (final version in versions) version.value];
  final names = [for (final version in versions) version.device];
  final sources = [
    for (final (index, version) in versions.indexed)
      _source(
        names[index],
        version.savedAt,
        // A second device of the same name also says when it saved.
        named: names.where((name) => name == names[index]).length == 1,
        now: now,
        clock: clock,
      ),
  ];
  final chapters = [
    for (final value in values) value == null ? null : _chapter(books, value),
  ];
  final kind = switch (record.collection) {
    'bookmarks' => 'bookmark',
    'history' => 'history entry',
    _ => 'saved place',
  };
  final value = values.nonNulls.firstOrNull;
  return ConflictLabels(
    title: _title(versions, books),
    kind: '${record.domain == 'audio' ? 'Listening' : 'Reading'} $kind',
    book: value == null ? null : _book(books, value),
    choices: [
      for (final (index, version) in versions.indexed)
        ChoiceLabel(
          identity: version.identity,
          source: sources[index],
          time: _time(values[index]),
          detail: _detail(values[index], chapters[index]),
          bookmarkTitle: [sources[index], ?chapters[index]].join(' · '),
        ),
    ],
    track: record.collection == 'resumes' ? _track(books, values) : null,
  );
}

/// The name of the book of the first nondeleted version.
String _title(List<ConflictVersion> versions, List<Book> books) =>
    switch (versions.map((version) => version.value).nonNulls.firstOrNull) {
      null => 'Book unavailable',
      final value => _bookName(books, value),
    };

/// The track of the listening places [values] in their edition of [books],
/// or null when one of them is no listening place in a known file of it.
ConflictTrack? _track(List<Book> books, List<RecordValue?> values) {
  final first = values.firstOrNull;
  final edition = first == null ? null : _edition(books, first.position);
  if (edition == null) return null;
  final outline = audioOutline(edition);
  final total = outline.length;
  if (total == null || total <= 0) return null;
  final places = <int>[];
  for (final value in values) {
    final position = value?.position;
    if (position is! AudioPosition || position.editionId != edition.id) {
      return null;
    }
    final known = edition.files.any(
      (file) =>
          file.key == position.sourceKey && file.revision == position.revision,
    );
    final offset = known ? outline.fileStarts[position.sourceKey] : null;
    if (offset == null) return null;
    places.add(offset + position.milliseconds);
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

/// The chapter of a listening place or the source page of a reading place.
String? _chapter(List<Book> books, RecordValue value) {
  final position = value.position;
  if (position is AudioPosition) {
    return _edition(books, position)?.files
        .where(
          (file) =>
              file.key == position.sourceKey &&
              file.revision == position.revision,
        )
        .firstOrNull
        ?.chapterAt(position.milliseconds);
  }
  final page = textAnchorPreview(position as TextPosition).page;
  return page == null ? null : 'Source page $page';
}

String? _time(RecordValue? value) => switch (value?.position) {
  AudioPosition(:final milliseconds) => audioTime(milliseconds),
  _ => null,
};

/// What [value] holds besides its time: its [chapter], or its reading
/// place, and the title and note of a bookmark.
String _detail(RecordValue? value, String? chapter) {
  if (value == null) return 'Keep deletion';
  final parts = <String>[?chapter];
  if (value.position case final TextPosition position) {
    final quote = textAnchorPreview(position).quote;
    parts.add(
      quote != null && quote.trim().isNotEmpty
          ? '“$quote”'
          : 'Saved reading place (preview unavailable)',
    );
  }
  if (value case BookmarkValue(:final bookmark)) {
    for (final text in [bookmark.title, bookmark.note]) {
      if (text != null && text.isNotEmpty) parts.add(text);
    }
  }
  return parts.join(' · ');
}

Edition? _edition(List<Book> books, Place position) => books
    .expand((book) => book.editions)
    .where((edition) => edition.id == position.editionId)
    .firstOrNull;

Book? _book(List<Book> books, RecordValue value) => books
    .where(
      (book) => book.editions.any(
        (edition) => edition.id == value.position.editionId,
      ),
    )
    .firstOrNull;

String _bookName(List<Book> books, RecordValue value) =>
    _book(books, value)?.title ??
    (value.bookTitle != null
        ? '${value.bookTitle} (not in the current library)'
        : 'Book not in the current library');
