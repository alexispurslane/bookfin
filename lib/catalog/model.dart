import 'dart:convert';

class CatalogEntry {
  CatalogEntry.fromJson(Map<String, dynamic> json, {required this.libraryId})
    : json = _freeze(json) as Map<String, dynamic>;
  final Map<String, dynamic> json;
  final String libraryId;
  String get id => json['Id'] as String;
  Map<String, dynamic> toJson() => {'library': libraryId, 'item': json};
}

enum EditionKind { audio, text }

class CatalogEdits {
  CatalogEdits({
    Map<String, String> bookLinks = const {},
    Map<String, String> recordingLinks = const {},
    Map<String, BookDetails> details = const {},
    Map<String, List<String>> fileOrders = const {},
  }) : bookLinks = Map.unmodifiable(bookLinks),
       recordingLinks = Map.unmodifiable(recordingLinks),
       details = Map.unmodifiable(details),
       fileOrders = Map.unmodifiable(
         fileOrders.map(
           (key, value) => MapEntry(key, List<String>.unmodifiable(value)),
         ),
       );
  final Map<String, String> bookLinks;
  final Map<String, String> recordingLinks;
  final Map<String, BookDetails> details;
  final Map<String, List<String>> fileOrders;
  factory CatalogEdits.fromJson(Map<String, dynamic> json) => CatalogEdits(
    bookLinks: Map<String, String>.from(json['books'] as Map? ?? {}),
    recordingLinks: Map<String, String>.from(json['recordings'] as Map? ?? {}),
    details: (json['details'] as Map<String, dynamic>? ?? {}).map(
      (key, value) =>
          MapEntry(key, BookDetails.fromJson(value as Map<String, dynamic>)),
    ),
    fileOrders: (json['orders'] as Map<String, dynamic>? ?? {}).map(
      (key, value) => MapEntry(key, List<String>.from(value as List)),
    ),
  );
  Map<String, dynamic> toJson() => {
    'books': bookLinks,
    'recordings': recordingLinks,
    'details': details.map((key, value) => MapEntry(key, value.toJson())),
    'orders': fileOrders,
  };
}

class BookDetails {
  const BookDetails({
    required this.title,
    required this.author,
    this.series,
    this.seriesOrder,
  });
  final String title;
  final String author;
  final String? series;
  final double? seriesOrder;
  factory BookDetails.fromJson(Map<String, dynamic> json) => BookDetails(
    title: json['title'] as String,
    author: json['author'] as String,
    series: json['series'] as String?,
    seriesOrder: (json['order'] as num?)?.toDouble(),
  );
  Map<String, dynamic> toJson() => {
    'title': title,
    'author': author,
    'series': series,
    'order': seriesOrder,
  };
}

class SourceFile {
  const SourceFile({
    required this.itemId,
    required this.displayName,
    required this.mediaSourceId,
    required this.revision,
    required this.durationMs,
    required this.container,
    required this.sizeBytes,
    this.chapters = const [],
    this.isItemOriginal = false,
  });
  final String itemId;
  final String displayName;
  final String mediaSourceId;

  /// Whether catalog metadata identifies the item original Download serves.
  final bool isItemOriginal;
  final String revision;
  final int? durationMs;
  final String container;
  final int? sizeBytes;
  final List<AudioChapter> chapters;
  String get key => '$itemId:$mediaSourceId';

  /// The chapters that a listener can reach in this file, in order. A file
  /// without a chapter at its start begins with a chapter named after the
  /// file. Chapters before the start or past the end are left out.
  List<AudioChapter> get playableChapters => [
    if (!chapters.any((chapter) => chapter.startMs == 0))
      AudioChapter(displayName, 0),
    for (final chapter in chapters)
      if (chapter.startMs >= 0 &&
          (durationMs == null || chapter.startMs < durationMs!))
        chapter,
  ];

  /// The name of the chapter of [playableChapters] that holds [milliseconds]
  /// into this file, which must not be negative.
  String chapterAt(int milliseconds) => playableChapters
      .where((chapter) => chapter.startMs <= milliseconds)
      .reduce(
        (found, chapter) => chapter.startMs >= found.startMs ? chapter : found,
      )
      .name;
}

class AudioChapter {
  const AudioChapter(this.name, this.startMs);
  final String name;
  final int startMs;
}

class Edition {
  const Edition({
    required this.id,
    required this.kind,
    required this.label,
    required this.files,
    required this.memberIds,
    this.narrator,
  });
  final String id;
  final EditionKind kind;
  final String label;

  /// The Jellyfin narrators of an audio edition, joined with commas.
  final String? narrator;
  final List<SourceFile> files;
  final List<String> memberIds;
}

/// The Jellyfin item whose primary image is a book cover, at one image version.
class CoverRef {
  const CoverRef(this.itemId, this.tag);
  final String itemId;

  /// Jellyfin's image tag. It changes when the image changes.
  final String tag;
  @override
  bool operator ==(Object other) =>
      other is CoverRef && other.itemId == itemId && other.tag == tag;
  @override
  int get hashCode => Object.hash(itemId, tag);
  @override
  String toString() => 'CoverRef($itemId, $tag)';
}

class Book {
  const Book({
    required this.id,
    required this.title,
    required this.author,
    required this.editions,
    this.series,
    this.seriesOrder,
    this.providerIds = const {},
    this.cover,
    this.description,
    this.genres = const [],
    this.publisher,
    this.year,
  });
  final String id;
  final String title;
  final String author;
  final List<Edition> editions;
  final String? series;
  final double? seriesOrder;
  final Map<String, String> providerIds;
  final CoverRef? cover;

  /// Plain text. Paragraphs are separated by one blank line.
  final String? description;
  final List<String> genres;
  final String? publisher;
  final int? year;
}

/// How many times this isolate ran [buildBooks]. Each isolate counts its own
/// builds, so a test reads it to prove that the catalog builds its books in
/// another isolate.
int get booksBuilt => _booksBuilt;
int _booksBuilt = 0;

List<Book> buildBooks(List<CatalogEntry> entries, {CatalogEdits? edits}) {
  _booksBuilt++;
  edits ??= CatalogEdits();
  final automatic = _seriesEditionLinks(entries);
  final byBook = <String, List<_SourceEdition>>{};
  for (final entry in entries) {
    final item = entry.json;
    final type = item['Type'];
    if (type != 'AudioBook' && type != 'Audio' && type != 'Book') {
      continue;
    }
    final kind = type == 'Book' ? EditionKind.text : EditionKind.audio;
    final sources = (item['MediaSources'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final unnamedBookOriginal = sources.isEmpty && type == 'Book';
    if (sources.isEmpty) sources.add({'Id': ''});
    for (final source in sources) {
      final sourceId = source['Id'] as String? ?? '';
      final editionId = '${entry.id}:$sourceId';
      final bookId =
          edits.bookLinks[editionId] ??
          automatic[entry.id] ??
          'book:${entry.id}';
      final file = SourceFile(
        itemId: entry.id,
        displayName: (item['Name'] as String?)?.trim().isNotEmpty == true
            ? item['Name'] as String
            : entry.id,
        mediaSourceId: sourceId,
        isItemOriginal:
            unnamedBookOriginal ||
            (identical(source, sources.first) &&
                sourceId == entry.id &&
                source['IsRemote'] != true &&
                (source['Type'] == null || source['Type'] == 'Default')),
        revision:
            [
              item['DateModified'],
              source['ETag'],
              item['Etag'],
            ].any((value) => value is String && value.isNotEmpty)
            ? jsonEncode([
                item['DateModified'],
                source['ETag'] ?? item['Etag'],
                source['Size'],
                source['Container'],
                source['RunTimeTicks'] ?? item['RunTimeTicks'],
              ])
            : '',
        durationMs: _milliseconds(
          source['RunTimeTicks'] ?? item['RunTimeTicks'],
        ),
        container:
            source['Container'] as String? ??
            item['Container'] as String? ??
            '',
        sizeBytes: (source['Size'] as num?)?.toInt(),
        chapters: List.unmodifiable(
          (item['Chapters'] as List? ?? [])
              .whereType<Map<String, dynamic>>()
              .map(
                (chapter) => AudioChapter(
                  chapter['Name'] as String? ?? 'Chapter',
                  _milliseconds(chapter['StartPositionTicks']) ?? 0,
                ),
              ),
        ),
      );
      byBook
          .putIfAbsent(bookId, () => [])
          .add(_SourceEdition(entry, editionId, kind, file));
    }
  }
  final books = <Book>[];
  for (final group in byBook.entries) {
    final seed = group.value.firstWhere(
      (source) => 'book:${source.entry.id}' == group.key,
      orElse: () => group.value.first,
    );
    final recordings = <String, List<_SourceEdition>>{};
    for (final source in group.value) {
      final targetId = edits.recordingLinks[source.id];
      final recordingId = source.kind == EditionKind.audio && targetId != null
          ? targetId
          : source.id;
      recordings.putIfAbsent(recordingId, () => []).add(source);
    }
    final editions = <Edition>[];
    for (final recording in recordings.entries) {
      final order = edits.fileOrders[recording.key] ?? const <String>[];
      recording.value.sort((left, right) {
        final leftExplicit = order.indexOf(left.file.key);
        final rightExplicit = order.indexOf(right.file.key);
        if (leftExplicit >= 0 || rightExplicit >= 0) {
          return (leftExplicit < 0 ? order.length : leftExplicit).compareTo(
            rightExplicit < 0 ? order.length : rightExplicit,
          );
        }
        final discOrder = _index(left.entry.json['ParentIndexNumber'])
            .compareTo(_index(right.entry.json['ParentIndexNumber']));
        if (discOrder != 0) return discOrder;
        final trackOrder = _index(left.entry.json['IndexNumber'])
            .compareTo(_index(right.entry.json['IndexNumber']));
        if (trackOrder != 0) return trackOrder;
        final nameOrder = naturalCompare(
          left.entry.json['Name'] as String? ?? '',
          right.entry.json['Name'] as String? ?? '',
        );
        return nameOrder != 0 ? nameOrder : left.id.compareTo(right.id);
      });
      final first = recording.value.first;
      final narrators = (first.entry.json['People'] as List? ?? [])
          .whereType<Map>()
          .where((person) => person['Type'] == 'Narrator')
          .map((person) => person['Name'])
          .join(', ');
      editions.add(
        Edition(
          id: recording.key,
          kind: first.kind,
          narrator: narrators.isEmpty ? null : narrators,
          label: narrators.isNotEmpty
              ? narrators
              : first.file.container.isNotEmpty
              ? first.file.container.toUpperCase()
              : first.kind == EditionKind.audio
              ? 'Audio'
              : 'Text',
          files: List.unmodifiable(
            recording.value.map((source) => source.file),
          ),
          memberIds: List.unmodifiable(
            recording.value.map((source) => source.id),
          ),
        ),
      );
    }
    final details = edits.details[group.key];
    final item = seed.entry.json;
    final own = _seriesOf(item);
    books.add(
      Book(
        id: group.key,
        title: details?.title ?? own.title,
        author: details?.author ?? _author(item),
        editions: List.unmodifiable(editions),
        series: details != null ? details.series : own.series,
        seriesOrder: details != null
            ? details.seriesOrder
            : own.series == null
            ? null
            : ([seed, ...group.value]
                      .map((source) => _seriesOf(source.entry.json))
                      .where(
                        (member) =>
                            member.series == own.series && member.order != null,
                      )
                      .toList()
                    ..sort((left, right) => right.trust - left.trust))
                  .firstOrNull
                  ?.order,
        providerIds: Map.unmodifiable(
          Map<String, String>.from(item['ProviderIds'] as Map? ?? {}),
        ),
        cover: [
          seed,
          ...group.value,
        ].map((source) => _cover(source.entry.json)).nonNulls.firstOrNull,
        description: _plainText(item['Overview']),
        genres: List.unmodifiable(
          (item['Genres'] as List? ?? []).whereType<String>(),
        ),
        publisher: (item['Studios'] as List? ?? [])
            .whereType<Map>()
            .map((studio) => _text(studio['Name']))
            .nonNulls
            .firstOrNull,
        year: (item['ProductionYear'] as num?)?.toInt(),
      ),
    );
  }
  return List.unmodifiable(sortedNaturally(books, (book) => book.title));
}

List<Book> possibleMatches(Book book, List<Book> books) => books
    .where(
      (candidate) =>
          candidate.id != book.id &&
          (titleMatchKey(candidate.title) == titleMatchKey(book.title) ||
              book.providerIds.entries.any(
                (identifier) =>
                    identifier.value.isNotEmpty &&
                    candidate.providerIds[identifier.key] == identifier.value,
              )),
    )
    .toList();

/// The form of a title that [possibleMatches] compares: lowercase, with only
/// its letters and digits.
String titleMatchKey(String title) =>
    title.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');

/// Ebook items that join an audiobook automatically, by item id, mapped to
/// the audiobook's book id. They join when both carry the same Jellyfin
/// series, title, and author, and exactly one audiobook item matches. Two
/// matching recordings are ambiguous, so nothing joins them.
Map<String, String> _seriesEditionLinks(List<CatalogEntry> entries) {
  final audio = <String, List<String>>{};
  final text = <String, List<String>>{};
  for (final entry in entries) {
    final item = entry.json;
    final type = item['Type'];
    if (type != 'AudioBook' && type != 'Book') continue;
    final (:title, :series, order: _, trust: _) = _seriesOf(item);
    if (series == null || title.isEmpty) continue;
    final key = jsonEncode([
      series.toLowerCase().replaceAll(RegExp(r'\s+'), ' '),
      title.toLowerCase(),
      _author(item).trim().toLowerCase(),
    ]);
    (type == 'Book' ? text : audio).putIfAbsent(key, () => []).add(entry.id);
  }
  return {
    for (final MapEntry(:key, value: ebooks) in text.entries)
      if (audio[key]?.length == 1)
        for (final id in ebooks) id: 'book:${audio[key]!.single}',
  };
}

/// A title with a series and a number in it, for example
/// "A Crown of Swords (The Wheel of Time #7)". Text can follow the series
/// part, as in "Queen Amid Ashes (The Sun Eater #4.5) by Christopher
/// Ruocchio". The last series part counts.
final _titledSeries = RegExp(
  r'^(.*\S)\s*\(\s*([^()#]*[^()#\s])\s*#\s*(\d+(?:\.\d+)?)\s*\)\s*(.*?)\s*$',
);

/// A title with a leading part before " - ", as in
/// "2.6 Sun Eater Series - Queen Amid Ashes".
final _leadingPart = RegExp(r'^(.*?\S)\s+[-–]\s+(\S.*)$');

/// What can come before a trailing credit, as in " by Christopher Ruocchio"
/// and "-Christopher Ruocchio".
final _creditSeparator = RegExp(r'\s+by\s+|\s*[-–]\s*', caseSensitive: false);

/// What separates the names in a credit or an author list.
final _nameSeparator = RegExp(r',|&|\band\b', caseSensitive: false);

/// The shown title of [item] in [series], from its [title] and its
/// "(Series #N)" part [match], if any. A file name can add noise around a
/// title: a leading label that names the series, as in "2.6 Sun Eater Series
/// - ", or only the authors, as in "Stephen Baxter - ", and a trailing credit
/// to the authors, as in " by Christopher Ruocchio". A series part or a series
/// label marks such a file name, and then the label and the credit go. A title
/// without either mark does not change.
String _shownTitle(
  String title,
  RegExpMatch? match,
  String series,
  Map<String, dynamic> item,
) {
  final core = match == null
      ? title
      : [
          match.group(1)!,
          match.group(4)!,
        ].where((part) => part.isNotEmpty).join(' ');
  final names = {
    _seriesLabelKey(series),
    if (match != null) _seriesLabelKey(match.group(2)!),
  }..remove('');
  final lead = _leadingPart.firstMatch(core);
  final labeled =
      lead != null && names.contains(_seriesLabelKey(lead.group(1)!));
  if (match == null && !labeled) return title;
  final rest =
      lead != null && (labeled || _creditsAuthors(lead.group(1)!, item))
      ? lead.group(2)!
      : core;
  for (final separator in _creditSeparator.allMatches(rest)) {
    if (separator.start > 0 &&
        _creditsAuthors(rest.substring(separator.end), item)) {
      return rest.substring(0, separator.start);
    }
  }
  return rest;
}

/// The form of a series name that a leading title part must match: its
/// letters only, without the words "the", "series", and "book". So
/// "2.6 Sun Eater Series" names "The Sun Eater", and "2" names nothing.
String _seriesLabelKey(String name) => name.toLowerCase().replaceAll(
  RegExp(r'\b(?:the|series|book)\b|[^\p{L}]', unicode: true),
  '',
);

/// Whether every name in [credit] is an author of [item].
bool _creditsAuthors(String credit, Map<String, dynamic> item) {
  String key(String name) =>
      name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  final authors = _author(item).split(_nameSeparator).map(key).toSet()
    ..remove('');
  return credit.split(_nameSeparator).map(key).every(authors.contains);
}

/// The series of one Jellyfin item, its position, and its title without a
/// series part. Sources, strongest first: the Jellyfin series field, the one
/// book collection that holds the item, and a "(Series #N)" title part. The
/// position comes from the title number, else from the item number. Plain
/// audio files are tracks, so they have no series.
({String title, String? series, double? order, int trust}) _seriesOf(
  Map<String, dynamic> item,
) {
  final name = (item['Name'] as String?)?.trim() ?? '';
  final title = name.isEmpty ? 'Untitled' : name;
  if (item['Type'] == 'Audio') {
    return (title: title, series: null, order: null, trust: 0);
  }
  final match = _titledSeries.firstMatch(name);
  final collections = (item['BookfinCollections'] as List? ?? [])
      .whereType<String>()
      .toList();
  final series =
      _text(item['SeriesName']) ??
      (collections.length == 1 ? _text(collections.single) : null) ??
      match?.group(2)!.trim();
  if (series == null) {
    return (title: title, series: null, order: null, trust: 0);
  }
  return (
    title: _shownTitle(title, match, series, item),
    series: series,
    order: match != null
        ? double.parse(match.group(3)!)
        : (item['IndexNumber'] as num?)?.toDouble(),
    // How much to trust the position: a title number, then an ebook's series
    // index, then an audiobook's item number, which can be a track number.
    trust: match != null
        ? 2
        : item['Type'] == 'Book'
        ? 1
        : 0,
  );
}

String? _text(dynamic value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;

CoverRef? _cover(Map<String, dynamic> item) {
  final own = (item['ImageTags'] as Map?)?['Primary'];
  if (own is String && own.isNotEmpty) {
    return CoverRef(item['Id'] as String, own);
  }
  final album = item['AlbumId'];
  final albumTag = item['AlbumPrimaryImageTag'];
  return album is String &&
          album.isNotEmpty &&
          albumTag is String &&
          albumTag.isNotEmpty
      ? CoverRef(album, albumTag)
      : null;
}

/// Jellyfin overviews from ebook metadata often hold HTML.
/// Jellyfin's description HTML as plain text: line breaks and paragraph
/// ends become new lines, other tags go, entities decode once, runs of
/// spaces and tabs become one space, spaces around new lines go, and at most
/// one blank line stays.
///
/// A restore cleans every book's description, so each pass runs only when
/// its text can match: most descriptions have no tags, entities or blank
/// lines. Measured on 1478 descriptions in AOT on an M-series Mac, an
/// unguarded pass that replaced every single space took 78 ms, and the
/// three-newline pass took 45 ms on text without new lines.
String? _plainText(dynamic value) {
  if (value is! String) return null;
  var text = value;
  if (text.contains('<')) {
    text = text
        .replaceAll(_lineBreak, '\n')
        .replaceAll(_paragraphEnd, '\n\n')
        .replaceAll(_tag, '');
  }
  if (text.contains('&')) {
    text = text
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&amp;', '&');
  }
  text = text.replaceAll(_blankRun, ' ');
  if (text.contains('\n')) text = text.replaceAll(_lineEdge, '\n');
  if (text.contains('\n\n\n')) text = text.replaceAll(_blankLines, '\n\n');
  text = text.trim();
  return text.isEmpty ? null : text;
}

final _lineBreak = RegExp(r'<br\s*/?>', caseSensitive: false);
final _paragraphEnd = RegExp(r'</p\s*>', caseSensitive: false);
final _tag = RegExp(r'<[^>]*>');

/// A run of spaces and tabs that is not one space alone. One space alone
/// stays as it is, so ordinary text needs no new string.
final _blankRun = RegExp(r'(?: [ \t]|\t)[ \t]*');
final _lineEdge = RegExp(r' *\n *');
final _blankLines = RegExp(r'\n{3,}');

int? _milliseconds(dynamic ticks) =>
    ticks is num ? ticks.toInt() ~/ 10000 : null;
int _index(dynamic index) => index is num ? index.toInt() : 0x7fffffff;
String _author(Map<String, dynamic> item) {
  final authors = (item['People'] as List? ?? [])
      .whereType<Map>()
      .where((person) => person['Type'] == 'Author')
      .map((person) => person['Name'])
      .join(', ');
  if (authors.isNotEmpty) return authors;
  return item['AlbumArtist'] as String? ??
      (item['Artists'] as List? ?? []).join(', ');
}

/// Compares two texts in natural order: letter case is ignored, and runs of
/// digits compare as numbers, so "Book 9" comes before "Book 10".
int naturalCompare(String left, String right) =>
    NaturalKey(left).compareTo(NaturalKey(right));

/// [items] in natural order of [name], with one key made per item instead of
/// two per comparison.
List<T> sortedNaturally<T>(Iterable<T> items, String Function(T) name) {
  final keyed = [
    for (final item in items) (key: NaturalKey(name(item)), item: item),
  ]..sort((left, right) => left.key.compareTo(right.key));
  return [for (final entry in keyed) entry.item];
}

/// A text split once into its lowercase runs of digits and of other
/// characters, for [naturalCompare] order.
class NaturalKey implements Comparable<NaturalKey> {
  factory NaturalKey(String text) {
    final parts = [
      for (final match in _naturalParts.allMatches(text.toLowerCase()))
        match[0]!,
    ];
    return NaturalKey._(parts, [for (final part in parts) int.tryParse(part)]);
  }
  const NaturalKey._(this._parts, this._numbers);
  final List<String> _parts;

  /// Each part's value when it is a number that fits an int, else null.
  final List<int?> _numbers;

  @override
  int compareTo(NaturalKey other) {
    for (
      var index = 0;
      index < _parts.length && index < other._parts.length;
      index++
    ) {
      final left = _numbers[index], right = other._numbers[index];
      final comparison = left != null && right != null
          ? left.compareTo(right)
          : _parts[index].compareTo(other._parts[index]);
      if (comparison != 0) return comparison;
    }
    return _parts.length.compareTo(other._parts.length);
  }
}

final _naturalParts = RegExp(r'\d+|\D+');

class _SourceEdition {
  const _SourceEdition(this.entry, this.id, this.kind, this.file);
  final CatalogEntry entry;
  final String id;
  final EditionKind kind;
  final SourceFile file;
}

dynamic _freeze(dynamic value) {
  if (value is Map<String, dynamic>) {
    return Map<String, dynamic>.unmodifiable(
      value.map((key, entry) => MapEntry(key, _freeze(entry))),
    );
  }
  if (value is List) return List<dynamic>.unmodifiable(value.map(_freeze));
  return value;
}

/// A place in one edition of a book: an [AudioPosition] or a
/// [TextPosition]. A switch on a place must cover both media.
sealed class Place {
  const Place();

  /// The id of the edition that holds the place.
  String get editionId;
}

class AudioPosition extends Place {
  const AudioPosition({
    required this.editionId,
    required this.sourceKey,
    required this.revision,
    required this.milliseconds,
  });
  @override
  final String editionId;
  final String sourceKey;
  final String revision;
  final int milliseconds;
  bool fits(Edition edition) =>
      edition.kind == EditionKind.audio &&
      edition.id == editionId &&
      revision.isNotEmpty &&
      milliseconds >= 0 &&
      edition.files.any(
        (file) =>
            file.mediaSourceId.isNotEmpty &&
            file.key == sourceKey &&
            file.revision == revision &&
            (file.durationMs == null || milliseconds <= file.durationMs!),
      );
}

class TextPosition extends Place {
  const TextPosition({
    required this.editionId,
    required this.sourceKey,
    required this.revision,
    required this.anchor,
    this.sourcePage,
  });
  @override
  final String editionId;
  final String sourceKey;
  final String revision;
  final String anchor;
  final int? sourcePage;
  bool fits(Edition edition) =>
      edition.kind == EditionKind.text &&
      edition.id == editionId &&
      revision.isNotEmpty &&
      anchor.isNotEmpty &&
      (sourcePage == null || sourcePage! > 0) &&
      edition.files.any(
        (file) => file.key == sourceKey && file.revision == revision,
      );
}
