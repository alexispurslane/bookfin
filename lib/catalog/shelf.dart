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

List<ShelfItem> shelf(
  List<Book> books,
  ShelfFilter filter,
  bool Function(Edition) downloaded,
) {
  bool has(Book book, EditionKind kind) =>
      book.editions.any((edition) => edition.kind == kind);
  final matching = books.where(
    (book) => switch (filter) {
      ShelfFilter.all => true,
      ShelfFilter.audio => has(book, EditionKind.audio),
      ShelfFilter.ebooks => has(book, EditionKind.text),
      ShelfFilter.downloaded => bookDownloaded(book, downloaded),
    },
  );
  final series = <String, List<Book>>{};
  final items = <ShelfItem>[];
  for (final book in matching) {
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
  return items
    ..sort((left, right) => naturalCompare(left.sortName, right.sortName));
}

/// Books whose title, author, or series contains the query. Never grouped.
List<Book> search(List<Book> books, String query) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return const [];
  return books
      .where(
        (book) => [
          book.title,
          book.author,
          ?book.series,
        ].any((field) => field.toLowerCase().contains(needle)),
      )
      .toList()
    ..sort((left, right) => naturalCompare(left.title, right.title));
}

String _seriesKey(String name) =>
    name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
