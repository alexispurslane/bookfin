import 'dart:isolate';
import 'dart:typed_data';

import 'package:bookfin/speech/book_search.dart';
import 'package:bookfin/speech/book_words.dart';
import 'package:flutter_test/flutter_test.dart';

/// Words that name the moment that they were read, so that a test can tell
/// one read from another.
Future<BookWords?> stamped() async => BookWords(
  ['${DateTime.now().microsecondsSinceEpoch}'],
  Int32List(1),
  bodyEnd: 1,
);

String first(BookWords words) => words.words.first;

void main() {
  test('reads a book once for several searches', () async {
    final search = BookSearch();
    addTearDown(search.close);
    final one = await search.withBook('a', stamped, first);
    final two = await search.withBook('a', stamped, first);
    expect(two, one);
  });

  test('keeps the words of the two latest books only', () async {
    final search = BookSearch();
    addTearDown(search.close);
    final a = await search.withBook('a', stamped, first);
    await search.withBook('b', stamped, first);
    expect(await search.withBook('a', stamped, first), a);
    await search.withBook('c', stamped, first);
    await search.withBook('b', stamped, first);
    // b and c are the latest, so a is read again.
    expect(await search.withBook('a', stamped, first), isNot(a));
  });

  test('a book that cannot be read gives nothing, and is read again later', () {
    final search = BookSearch();
    addTearDown(search.close);
    return expectLater(
      search.withBook('a', () async => null, first).then((missing) async {
        expect(missing, isNull);
        return search.withBook('a', stamped, first);
      }),
      completion(isNotNull),
    );
  });

  test('searches run in the worker, off the calling isolate', () async {
    final search = BookSearch();
    addTearDown(search.close);
    final name = await search.withBook(
      'a',
      stamped,
      (_) => Isolate.current.debugName,
    );
    expect(name, isNot(Isolate.current.debugName));
  });

  test('an idle worker lets the words go and reads them again', () async {
    final search = BookSearch(idle: const Duration(milliseconds: 20));
    addTearDown(search.close);
    final one = await search.withBook('a', stamped, first);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(await search.withBook('a', stamped, first), isNot(one));
  });

  test('an error of the work reaches the caller', () async {
    final search = BookSearch();
    addTearDown(search.close);
    await expectLater(
      search.withBook('a', stamped, (_) => throw StateError('broken')),
      throwsA(anything),
    );
    expect(await search.withBook('a', stamped, first), isNotNull);
  });
}
