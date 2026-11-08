import 'model.dart';

/// Which books the library shows. A filter applies to single books, before
/// books are grouped into series.
enum ShelfFilter { all, audio, ebooks, downloaded }

/// One entry of the library: a single book, or a series of two or more books.
sealed class ShelfItem {
  const ShelfItem();
  String get sortName;
}

class ShelfBook extends ShelfItem {
  const ShelfBook(this.book);
  final Book book;
  @override
  String get sortName => book.title;
}

class ShelfSeries extends ShelfItem {
  const ShelfSeries(this.name, this.books);
  final String name;

  /// In reading order.
  final List<Book> books;
  @override
  String get sortName => name;
}

/// A book is downloaded when its audio is. A book without audio is
/// downloaded when one of its ebook editions is.
bool bookDownloaded(Book book, bool Function(Edition) downloaded) {
  final audio = book.editions.where(
    (edition) => edition.kind == EditionKind.audio,
  );
  return (audio.isEmpty ? book.editions : audio).any(downloaded);
}

/// Whether [filter] keeps [book] on the shelf. [downloaded] is read only for
/// [ShelfFilter.downloaded].
bool bookMatches(
  Book book,
  ShelfFilter filter,
  bool Function(Edition) downloaded,
) {
  bool has(EditionKind kind) =>
      book.editions.any((edition) => edition.kind == kind);
  return switch (filter) {
    ShelfFilter.all => true,
    ShelfFilter.audio => has(EditionKind.audio),
    ShelfFilter.ebooks => has(EditionKind.text),
    ShelfFilter.downloaded => bookDownloaded(book, downloaded),
  };
}

/// Series position first, then publication year, then title. Books without a
/// value for a key follow the books that have one. A book without a position
/// takes the position of a book with the same title, so an audiobook sits
/// next to its ebook.
List<Book> readingOrder(Iterable<Book> books) {
  final positions = <String, double>{
    for (final book in books)
      if (book.seriesOrder != null) _titleKey(book.title): book.seriesOrder!,
  };
  double? position(Book book) =>
      book.seriesOrder ?? positions[_titleKey(book.title)];
  int? missingLast(Object? left, Object? right) => left == null
      ? (right == null ? null : 1)
      : right == null
      ? -1
      : null;
  return books.toList()..sort((left, right) {
    final leftPosition = position(left), rightPosition = position(right);
    final order =
        missingLast(leftPosition, rightPosition) ??
        (leftPosition == null ? 0 : leftPosition.compareTo(rightPosition!));
    if (order != 0) return order;
    final explicit = missingLast(left.seriesOrder, right.seriesOrder) ?? 0;
    if (explicit != 0) return explicit;
    final year =
        missingLast(left.year, right.year) ??
        (left.year == null ? 0 : left.year!.compareTo(right.year!));
    return year != 0 ? year : naturalCompare(left.title, right.title);
  });
}

String _titleKey(String title) => title.trim().toLowerCase();

/// The library entries of the [books] that pass [filter]: single books, and
/// series of two or more books, in natural order of their names.
///
/// The result is kept for this exact [books] list and [filter], and it is
/// given back unchanged, the same list, while the same books pass the
/// filter. So a caller can call this on every build, and a change of download
/// state regroups only a shelf that it changes. [books] must not change in
/// place after this call. The catalog publishes a new list on every change.
List<ShelfItem> shelf(
  List<Book> books,
  ShelfFilter filter,
  bool Function(Edition) downloaded,
) {
  final matching = books
      .where((book) => bookMatches(book, filter, downloaded))
      .toList();
  final shelves = _shelves[books] ??= {};
  final kept = shelves[filter];
  if (kept != null && _sameBooks(kept.matching, matching)) return kept.items;
  final items = _group(matching);
  shelves[filter] = (matching: matching, items: items);
  return items;
}

/// The last shelf of each filter, for each catalog book list. An entry goes
/// away with its list.
final _shelves =
    Expando<Map<ShelfFilter, ({List<Book> matching, List<ShelfItem> items})>>();

bool _sameBooks(List<Book> left, List<Book> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (!identical(left[index], right[index])) return false;
  }
  return true;
}

List<ShelfItem> _group(List<Book> books) {
  final series = <String, List<Book>>{};
  final items = <ShelfItem>[];
  for (final book in books) {
    if (book.series == null) {
      items.add(ShelfBook(book));
    } else {
      series.putIfAbsent(_seriesKey(book.series!), () => []).add(book);
    }
  }
  for (final members in series.values) {
    if (members.length == 1) {
      items.add(ShelfBook(members.single));
    } else {
      final ordered = readingOrder(members);
      items.add(ShelfSeries(ordered.first.series!.trim(), ordered));
    }
  }
  return List.unmodifiable(sortedNaturally(items, (item) => item.sortName));
}

/// Books whose title, author, or series contains the query. Never grouped.
List<Book> search(List<Book> books, String query) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return const [];
  return sortedNaturally(
    books.where(
      (book) => [
        book.title,
        book.author,
        ?book.series,
      ].any((field) => field.toLowerCase().contains(needle)),
    ),
    (book) => book.title,
  );
}

String _seriesKey(String name) =>
    name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// The books of one catalog, with the shelves and indexes that the library
/// pages read. The catalog builds a library off the UI isolate, once for each
/// change of its books, so that a page finds a shelf, a series, a book, its
/// possible matches or search results without a scan of the whole library.
///
/// A library never changes after it is built.
///
/// Invariant: every shelf and index is the one that [CatalogLibrary.build]
/// makes from [books]. [checkInvariants] proves it.
class CatalogLibrary {
  CatalogLibrary._({
    required this.books,
    required this._shelves,
    required this._positions,
    required this._seriesOfBook,
    required this._seriesByName,
    required this._sameTitle,
    required this._sameIdentifier,
    required this._searchText,
  });

  /// Groups and indexes [books], which must be in natural order of their
  /// titles, as [buildBooks] gives them. This is whole-library work, so the
  /// catalog runs it in another isolate.
  factory CatalogLibrary.build(List<Book> books) {
    bool has(Book book, EditionKind kind) =>
        book.editions.any((edition) => edition.kind == kind);
    final shelves = {
      ShelfFilter.all: _group(books),
      ShelfFilter.audio: _group([
        for (final book in books)
          if (has(book, EditionKind.audio)) book,
      ]),
      ShelfFilter.ebooks: _group([
        for (final book in books)
          if (has(book, EditionKind.text)) book,
      ]),
    };
    final sameTitle = <String, List<int>>{};
    final sameIdentifier = <String, List<int>>{};
    for (final (index, book) in books.indexed) {
      sameTitle.putIfAbsent(titleMatchKey(book.title), () => []).add(index);
      for (final identifier in book.providerIds.entries) {
        if (identifier.value.isEmpty) continue;
        sameIdentifier
            .putIfAbsent(
              _identifierKey(identifier.key, identifier.value),
              () => [],
            )
            .add(index);
      }
    }
    final series = shelves[ShelfFilter.all]!.whereType<ShelfSeries>();
    return CatalogLibrary._(
      books: books,
      shelves: shelves,
      positions: {for (final (index, book) in books.indexed) book.id: index},
      seriesOfBook: {
        for (final entry in series)
          for (final book in entry.books) book.id: entry,
      },
      seriesByName: {for (final entry in series) entry.name: entry},
      sameTitle: sameTitle,
      sameIdentifier: sameIdentifier,
      searchText: [for (final book in books) _searchTextOf(book)],
    );
  }

  /// The library of a signed-out account, or of an account without access.
  static final empty = CatalogLibrary.build(const []);

  /// In natural order of their titles.
  final List<Book> books;

  /// The shelves of the filters that need no download state.
  final Map<ShelfFilter, List<ShelfItem>> _shelves;

  /// The index of each book in [books], by book id.
  final Map<String, int> _positions;

  /// The series entry of the full shelf that holds each book, by book id.
  final Map<String, ShelfSeries> _seriesOfBook;

  /// The series entries of the full shelf, by name. Two series never share a
  /// name, because the shelf groups series by their name without case and
  /// spacing.
  final Map<String, ShelfSeries> _seriesByName;

  /// The indexes of the books with each title, as [possibleMatches] compares
  /// titles.
  final Map<String, List<int>> _sameTitle;

  /// The indexes of the books with each nonempty provider identifier.
  final Map<String, List<int>> _sameIdentifier;

  /// The lowercase title, author and series of each book, in [books] order.
  final List<String> _searchText;

  /// The library entries of the books that pass [filter], as [shelf] gives
  /// them. The shelves of all books, audio and ebooks are ready, so the call
  /// costs nothing, and it gives back the same list on every call.
  /// [downloaded] is read only for [ShelfFilter.downloaded]. That shelf is
  /// grouped here, on the calling isolate: it holds only the downloaded
  /// books, and grouping a few hundred books costs less than one isolate hop
  /// (about 1 ms for 500 books, measured in AOT), while the hop would copy
  /// every book to the other isolate. The downloaded shelf keeps its list
  /// while the same books are downloaded.
  List<ShelfItem> shelf(
    ShelfFilter filter,
    bool Function(Edition) downloaded,
  ) => _shelves[filter] ?? _shelf(books, filter, downloaded);

  /// The series of the full shelf whose name is [name], or null.
  ShelfSeries? series(String name) => _seriesByName[name];

  /// The series entry of the full shelf that holds [book], or null when the
  /// book is not in a series of two or more books of this library.
  ShelfSeries? seriesOf(Book book) => _seriesOfBook[book.id];

  /// The book whose id is [id], or null.
  Book? book(String id) {
    final index = _positions[id];
    return index == null ? null : books[index];
  }

  /// The other books of this library that may be the same work as [book],
  /// in [books] order: the books with the same title, as [possibleMatches]
  /// compares titles, and the books that share a provider identifier.
  List<Book> matches(Book book) {
    final found = <int>{
      ...?_sameTitle[titleMatchKey(book.title)],
      for (final identifier in book.providerIds.entries)
        if (identifier.value.isNotEmpty)
          ...?_sameIdentifier[_identifierKey(identifier.key, identifier.value)],
    };
    return [
      for (final index in found.toList()..sort())
        if (books[index].id != book.id) books[index],
    ];
  }

  /// The books whose title, author or series contains [query], ignoring
  /// letter case, in natural order of their titles, as [search] gives them.
  /// This runs on the calling isolate: the lowercase text of every book is
  /// ready, so a search is one substring test for each book, about 0.5 ms
  /// for 5000 books. A hop to another isolate would copy the library and
  /// cost more than that.
  List<Book> search(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return const [];
    return [
      for (final (index, text) in _searchText.indexed)
        if (text.contains(needle)) books[index],
    ];
  }

  /// Throws a [StateError] unless every shelf and index is the one that a
  /// new build from [books] makes. It rebuilds the library, so it is slow.
  void checkInvariants() {
    final fresh = CatalogLibrary.build(books);
    for (final filter in fresh._shelves.keys) {
      if (!_sameItems(_shelves[filter]!, fresh._shelves[filter]!)) {
        throw StateError('The $filter shelf must group the library books.');
      }
    }
    for (final (index, book) in books.indexed) {
      if (_positions[book.id] != index) {
        throw StateError('Each book id must lead to its book.');
      }
      final series = _seriesOfBook[book.id];
      if (series?.name != fresh._seriesOfBook[book.id]?.name ||
          (series != null &&
              !series.books.any((member) => identical(member, book)))) {
        throw StateError('Each book must lead to the series that holds it.');
      }
      if (_searchText[index] != fresh._searchText[index]) {
        throw StateError('The search text must follow each book.');
      }
      if (!_sameBooks(matches(book), possibleMatches(book, books))) {
        throw StateError('The possible matches must follow the books.');
      }
    }
    for (final series in fresh._seriesByName.values) {
      if (!identical(
        _seriesByName[series.name],
        _seriesOfBook[series.books.first.id],
      )) {
        throw StateError('Each series name must lead to its series.');
      }
    }
    if (_positions.length != books.length ||
        _seriesOfBook.length != fresh._seriesOfBook.length ||
        _seriesByName.length != fresh._seriesByName.length) {
      throw StateError('The indexes must hold only the library books.');
    }
  }
}

/// [shelf], under a name that [CatalogLibrary.shelf] does not hide.
const _shelf = shelf;

String _identifierKey(String provider, String value) => '$provider\n$value';

String _searchTextOf(Book book) =>
    [book.title, book.author, ?book.series].join('\n').toLowerCase();

bool _sameItems(List<ShelfItem> left, List<ShelfItem> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    final same = switch ((left[index], right[index])) {
      (ShelfBook(book: final a), ShelfBook(book: final b)) => identical(a, b),
      (
        ShelfSeries(name: final a, books: final x),
        ShelfSeries(name: final b, books: final y),
      ) =>
        a == b && _sameBooks(x, y),
      _ => false,
    };
    if (!same) return false;
  }
  return true;
}
