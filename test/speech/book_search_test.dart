import 'dart:isolate';
import 'dart:typed_data';

import 'package:bookfin/speech/book_search.dart';
import 'package:bookfin/speech/book_words.dart';
import 'package:bookfin/reader/epub/publication.dart';
import 'package:bookfin/reader/text_outline.dart';
import 'package:flutter_test/flutter_test.dart';

import '../real_time.dart';
import 'held_jobs.dart';
import 'book_words_test.dart' show book;
import '../reader/section_publication.dart';

ReadBook countedRead(
  Publication publication,
  TextOutline outline,
  SendPort report,
) => () async {
  final sections = CountedSections(publication.textFiles);
  final words = bookWordsOf(SectionPublication(publication, sections), outline);
  report.send(sections.reads);
  return words;
};

/// Words that name the moment that they were read, so that a test can tell
/// one read from another.
Future<BookWords?> stamped() async => BookWords(
  ['${DateTime.now().microsecondsSinceEpoch}'],
  Int32List(1),
  bodyEnd: 1,
);

String first(BookWords words) => words.words.first;

/// A read that gives the words once the test lets it go on.
ReadBook slow(SendPort ready) => () async {
  await held(ready);
  return stamped();
};

void main() {
  test(
    'a worker reads each section once when its outline is already owned',
    () async {
      final publication = book(['<p>Call me Ishmael.</p>', '<p>The end.</p>']);
      final reports = ReceivePort();
      addTearDown(reports.close);
      final report = reports.first;
      final search = BookSearch();
      addTearDown(search.close);
      final found = await search.withBook(
        'edition:r1',
        countedRead(
          publication,
          measureTextOutline(publication),
          reports.sendPort,
        ),
        (words) => (words.words, Isolate.current.debugName),
      );
      expect(found!.$1, ['call', 'me', 'ishmael', 'the', 'end']);
      expect(found.$2, isNot(Isolate.current.debugName));
      final reads = await report as Map;
      expect([for (final path in publication.spine) reads[path]], [1, 1]);
    },
  );

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

  // On the fake clock of a widget test: see worker_test.dart.
  testWidgets('a first read of a book that takes hours is not cut short', (
    tester,
  ) async {
    final search = BookSearch();
    final ready = Signal();
    addTearDown(ready.close);
    final found = ending(search.withBook('a', slow(ready.send), first));
    await runUntil(tester, () => ready.got);
    await tester.pump(const Duration(hours: 5));
    expect(found.ended, isFalse);
    release(ready);
    await runUntil(tester, () => found.ended);
    expect(found.value, isNotNull);
    await finish(tester, search.close());
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
