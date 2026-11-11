import 'book_words.dart';
import 'worker.dart';

/// Reads the words of an ebook. It runs in the worker isolate of a
/// [BookSearch], so it captures only plain data, such as a file path.
typedef ReadBook = Future<BookWords?> Function();

/// The words of the latest ebooks, kept in one worker isolate, and the
/// searches of heard words in them (docs/plans/cross-edition-places.md,
/// "Build design of S2"). A book of 456,000 words takes about 125 ms to
/// read and index on the Mac, and a search of all of it up to 44 ms, so
/// both stay off the UI isolate (engine rule 1). The worker keeps the two
/// latest books, and lets them go when it stops after [idle] without work.
class BookSearch {
  BookSearch({Duration idle = const Duration(minutes: 2)})
    : _worker = KeptWorker(
        () => <String, BookWords>{},
        name: 'book search',
        idle: idle,
      );

  final KeptWorker<Map<String, BookWords>> _worker;

  /// How many books the worker keeps.
  static const _kept = 2;

  /// What [work] gives for the words of the ebook [key], in the worker
  /// isolate. The worker reads the words with [read], unless it keeps them,
  /// and then keeps them. Null when [read] gives null, which is not kept,
  /// so a later request reads again. [key] names the edition and its file
  /// revision. [work] travels to the worker too, so it captures only plain
  /// data, and its result travels back.
  Future<T?> withBook<T>(
    String key,
    ReadBook read,
    T Function(BookWords words) work,
  ) => _worker.run((books) async {
    // Each use moves the book to the end, so the first is the oldest.
    final words = books.remove(key) ?? await read();
    if (words == null) return null;
    books[key] = words;
    while (books.length > _kept) {
      books.remove(books.keys.first);
    }
    return work(words);
  });

  Future<void> close() => _worker.close();
}
