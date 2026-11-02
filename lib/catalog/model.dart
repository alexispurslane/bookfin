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
  });
  final String id;
  final EditionKind kind;
  final String label;
  final List<SourceFile> files;
  final List<String> memberIds;
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
  });
  final String id;
  final String title;
  final String author;
  final List<Edition> editions;
  final String? series;
  final double? seriesOrder;
  final Map<String, String> providerIds;
}

List<Book> buildBooks(List<CatalogEntry> entries, {CatalogEdits? edits}) {
  edits ??= CatalogEdits();
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
      final bookId = edits.bookLinks[editionId] ?? 'book:${entry.id}';
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
        final nameOrder = _naturalCompare(
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
    books.add(
      Book(
        id: group.key,
        title:
            details?.title ?? seed.entry.json['Name'] as String? ?? 'Untitled',
        author: details?.author ?? _author(seed.entry.json),
        editions: List.unmodifiable(editions),
        series: details?.series,
        seriesOrder: details?.seriesOrder,
        providerIds: Map.unmodifiable(
          Map<String, String>.from(
            seed.entry.json['ProviderIds'] as Map? ?? {},
          ),
        ),
      ),
    );
  }
  books.sort((left, right) => _naturalCompare(left.title, right.title));
  return List.unmodifiable(books);
}

List<Book> possibleMatches(Book book, List<Book> books) => books
    .where(
      (candidate) =>
          candidate.id != book.id &&
          (_title(candidate.title) == _title(book.title) ||
              book.providerIds.entries.any(
                (identifier) =>
                    identifier.value.isNotEmpty &&
                    candidate.providerIds[identifier.key] == identifier.value,
              )),
    )
    .toList();

String _title(String title) =>
    title.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');
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

int _naturalCompare(String left, String right) {
  final parts = RegExp(r'\d+|\D+');
  final leftParts = parts
      .allMatches(left.toLowerCase())
      .map((match) => match[0]!)
      .toList();
  final rightParts = parts
      .allMatches(right.toLowerCase())
      .map((match) => match[0]!)
      .toList();
  for (
    var index = 0;
    index < leftParts.length && index < rightParts.length;
    index++
  ) {
    final leftNumber = int.tryParse(leftParts[index]);
    final rightNumber = int.tryParse(rightParts[index]);
    final comparison = leftNumber != null && rightNumber != null
        ? leftNumber.compareTo(rightNumber)
        : leftParts[index].compareTo(rightParts[index]);
    if (comparison != 0) return comparison;
  }
  return leftParts.length.compareTo(rightParts.length);
}

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

class AudioPosition {
  const AudioPosition({
    required this.editionId,
    required this.sourceKey,
    required this.revision,
    required this.milliseconds,
  });
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

class TextPosition {
  const TextPosition({
    required this.editionId,
    required this.sourceKey,
    required this.revision,
    required this.anchor,
    this.sourcePage,
  });
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
