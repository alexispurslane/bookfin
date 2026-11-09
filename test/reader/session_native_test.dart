// The reader session opens EPUB and MOBI books in the native pager. These
// tests drive the session as the reader screen does, with the real pager,
// and stand in for the viewport: they present page settings to the
// session's pager, as the native viewport does (tc-1iap). They check what
// the session shows and what it saves, so that the switch from the WebView
// reader loses or overwrites no saved place, bookmark or history entry.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/playback/records.dart';
import 'package:bookfin/reader/book_map.dart';
import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/epub/dom.dart';
import 'package:bookfin/reader/epub/layout.dart';
import 'package:bookfin/reader/epub/page_source.dart';
import 'package:bookfin/reader/epub/pager.dart';
import 'package:bookfin/reader/epub/places.dart';
import 'package:bookfin/reader/epub/prepare.dart';
import 'package:bookfin/reader/epub/publication.dart';
import 'package:bookfin/reader/platform_io.dart';
import 'package:bookfin/reader/session.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback/playback_test.dart' show account, LocalFiles, MemoryResume;
import 'epub/corpus/book.dart' show showcaseBooks;
import 'epub/epubjs_fixtures.dart'
    show fixture, immediateSource, pageAt, recordedSizes;
import 'epub/helpers.dart' show loadReaderFont, readerPage;
import 'epub/page_source_test.dart' show paragraphs;

SourceFile file(String container) => SourceFile(
  itemId: 'ebook',
  displayName: 'Book.$container',
  mediaSourceId: 'original',
  revision: 'revision-one',
  durationMs: null,
  container: container,
  sizeBytes: 100,
);

Edition editionOf(SourceFile source) => Edition(
  id: 'text-edition',
  kind: EditionKind.text,
  label: source.container.toUpperCase(),
  files: [source],
  memberIds: const ['ebook'],
);

final epubFile = file('epub');
final epubEdition = editionOf(epubFile);
Book bookOf(Edition edition) =>
    Book(id: 'work', title: 'River', author: 'Writer', editions: [edition]);

final accountKey = account().scope.key;

/// A reading store that keeps each change that the session hands it.
class SpyStore extends MemoryResume {
  final saves = <ReadingChanges>[];

  @override
  Future<void> saveReading(String accountKey, ReadingChanges changes) {
    saves.add(changes);
    return super.saveReading(accountKey, changes);
  }

  /// Every resume that the session saved, as JSON.
  List<Map<String, dynamic>> get savedResumes => [
    for (final changes in saves) ...changes.resumes,
  ];

  /// Every bookmark change that the session saved.
  List<Map<String, dynamic>?> get savedBookmarks => [
    for (final changes in saves) ...changes.bookmarks.values,
  ];
}

/// The saved form of [location] as the session wrote it while the WebView
/// reader reported places: the reported JSON, decoded as a location, then
/// saved by the document.
String anchorOf(ReaderDocument document, Map<String, dynamic> location) =>
    jsonEncode(document.save(EpubAddress(ReadingLocation.fromJson(location))));

TextPosition positionAt(String anchor, [Edition? edition]) {
  final source = (edition ?? epubEdition).files.single;
  return TextPosition(
    editionId: (edition ?? epubEdition).id,
    sourceKey: source.key,
    revision: source.revision,
    anchor: anchor,
  );
}

Map<String, dynamic> bookmarkAt(String id, String anchor) => TextBookmark(
  id: id,
  position: positionAt(anchor),
  createdAt: DateTime.utc(2026, 11, 1),
  title: 'Saved $id',
).toJson();

/// The reading snapshot of an account with [resumes] and [bookmarks].
Map<String, dynamic> snapshot({
  List<String> resumes = const [],
  List<Map<String, dynamic>> bookmarks = const [],
  num fontSize = 20,
}) => {
  'version': 1,
  'fontSize': fontSize,
  'resumes': [
    for (final anchor in resumes) encodeTextPosition(positionAt(anchor)),
  ],
  'bookmarks': bookmarks,
};

/// Whether [page] holds the character of [dom] at [place], or the first
/// visible one after it.
bool holds(LaidPage page, DomSection dom, EpubPlace place) {
  final at = dom.visibleBefore(place);
  return page.section == place.section &&
      page.startVisible <= at &&
      at < page.endVisible;
}

/// Whether the first line of [page] holds the character of [dom] at
/// [place], or the first visible one after it.
bool firstLineHolds(LaidPage page, DomSection dom, EpubPlace place) {
  final at = dom.visibleBefore(place);
  final starts = page.lineStarts;
  if (page.section != place.section || starts.isEmpty) return false;
  final end = starts.length > 1 ? starts[1] : page.endVisible;
  return starts.first <= at && at < end;
}

/// What identifies a shown page: its section, its start and its first and
/// last places.
List<Object?> identity(LaidPage page) => [
  page.section,
  page.start,
  page.startPlace,
  page.endPlace,
];

/// An EPUB 3 book with a navigation document. Each of [bodies] is one
/// section; [toc] lists the contents as (title, href) pairs, relative to
/// the package document.
Uint8List navBook(List<String> bodies, List<(String, String)> toc) {
  final entries = <String, String>{
    'META-INF/container.xml':
        '<container><rootfiles><rootfile full-path="OPS/book.opf"/>'
        '</rootfiles></container>',
    'OPS/book.opf':
        '<package xmlns="http://www.idpf.org/2007/opf" version="3.0">'
        '<metadata/><manifest>'
        '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" '
        'properties="nav"/>'
        '${[for (var i = 0; i < bodies.length; i++) '<item id="s$i" href="text/s$i.xhtml" media-type="application/xhtml+xml"/>'].join()}'
        '</manifest><spine>'
        '${[for (var i = 0; i < bodies.length; i++) '<itemref idref="s$i"/>'].join()}'
        '</spine></package>',
    'OPS/nav.xhtml':
        '<html xmlns="http://www.w3.org/1999/xhtml" '
        'xmlns:epub="http://www.idpf.org/2007/ops"><head><title>Contents'
        '</title></head><body><nav epub:type="toc"><ol>'
        '${[for (final (title, href) in toc) '<li><a href="$href">$title</a></li>'].join()}'
        '</ol></nav></body></html>',
    for (final (i, body) in bodies.indexed)
      'OPS/text/s$i.xhtml':
          '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Part'
          '</title></head><body>$body</body></html>',
  };
  final archive = Archive()
    ..add(
      ArchiveFile.noCompress(
        'mimetype',
        20,
        utf8.encode('application/epub+zip'),
      ),
    );
  for (final MapEntry(key: path, value: text) in entries.entries) {
    archive.add(ArchiveFile.string(path, text));
  }
  return ZipEncoder().encodeBytes(archive);
}

/// An EPUB 2 book without contents whose spine lists [bodies] in order,
/// each with its `linear` attribute, or none.
Uint8List bookWithoutContents(List<(String, String?)> bodies) {
  final entries = <String, String>{
    'META-INF/container.xml':
        '<container><rootfiles><rootfile full-path="OPS/book.opf"/>'
        '</rootfiles></container>',
    'OPS/book.opf':
        '<package xmlns="http://www.idpf.org/2007/opf" version="2.0">'
        '<metadata/><manifest>'
        '${[for (var i = 0; i < bodies.length; i++) '<item id="s$i" href="text/s$i.xhtml" media-type="application/xhtml+xml"/>'].join()}'
        '</manifest><spine>'
        '${[for (final (i, (_, linear)) in bodies.indexed) '<itemref idref="s$i"${linear == null ? '' : ' linear="$linear"'}/>'].join()}'
        '</spine></package>',
    for (final (i, (body, _)) in bodies.indexed)
      'OPS/text/s$i.xhtml':
          '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Part'
          '</title></head><body>$body</body></html>',
  };
  final archive = Archive()
    ..add(
      ArchiveFile.noCompress(
        'mimetype',
        20,
        utf8.encode('application/epub+zip'),
      ),
    );
  for (final MapEntry(key: path, value: text) in entries.entries) {
    archive.add(ArchiveFile.string(path, text));
  }
  return ZipEncoder().encodeBytes(archive);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadReaderFont);

  late LocalFiles downloads;
  late SpyStore store;
  final sessions = <ReaderSession>[];
  final sources = <PageSource>[];

  setUp(() {
    downloads = LocalFiles()..files[epubFile.key] = Uri.file('/verified.epub');
    store = SpyStore();
  });
  tearDown(() {
    for (final session in sessions) {
      session.dispose();
    }
    sessions.clear();
    for (final source in sources) {
      source.dispose();
    }
    sources.clear();
    downloads.dispose();
  });

  /// A new session of the account, as after a restart.
  ReaderSession sessionOf(
    Publication? publication, {
    DocumentLoader? loadDocument,
  }) {
    final reader = ReaderSession(
      downloads: downloads,
      store: store,
      load: (_) async => publication!,
      loadDocument: loadDocument,
    );
    sessions.add(reader);
    return reader;
  }

  /// Opens [publication] in a new session of the account.
  Future<ReaderSession> open(
    Publication? publication, {
    Edition? edition,
    DocumentLoader? loadDocument,
  }) async {
    final chosen = edition ?? epubEdition;
    final reader = sessionOf(publication, loadDocument: loadDocument);
    await reader.bind(account(), [bookOf(chosen)]);
    await reader.open(bookOf(chosen), chosen);
    reader.checkInvariants();
    return reader;
  }

  /// The DOM of section [index] of [publication].
  Future<DomSection> domOf(Publication publication, int index) async {
    final source = immediateSource(publication)..settings = readerPage;
    sources.add(source);
    return (await source.section(index)).dom;
  }

  /// The first page that the pager shows that passes [test].
  Future<ShownPage> shownWhere(
    EpubPager pager,
    bool Function(ShownPage shown) test,
  ) {
    final now = pager.shown.value;
    if (now != null && test(now)) return Future.value(now);
    final found = Completer<ShownPage>();
    void listener() {
      final shown = pager.shown.value;
      if (shown != null && test(shown) && !found.isCompleted) {
        found.complete(shown);
      }
    }

    pager.shown.addListener(listener);
    return found.future
        .timeout(const Duration(seconds: 30))
        .whenComplete(() => pager.shown.removeListener(listener));
  }

  /// Presents [settings] to the session's pager, as the viewport does, and
  /// waits for the page that it shows for them.
  Future<LaidPage> present(
    ReaderSession reader, [
    PageSettings settings = readerPage,
  ]) async {
    expect(
      reader.pager,
      isNotNull,
      reason: 'The session opens the book in the pager.',
    );
    final pager = reader.pager!;
    final before = pager.shown.value?.page;
    pager.present(settings);
    final shown = await shownWhere(
      pager,
      (shown) =>
          shown.page.settings == settings && !identical(shown.page, before),
    );
    await reader.flush();
    reader.checkInvariants();
    return shown.page;
  }

  /// The book map of the open book, once the session measured it.
  Future<BookMap> mapped(ReaderSession reader) {
    if (reader.bookMap case final map?) return Future.value(map);
    final done = Completer<BookMap>();
    void listener() {
      if (reader.bookMap case final map? when !done.isCompleted) {
        done.complete(map);
      }
    }

    reader.bookMapChanges.addListener(listener);
    return done.future
        .timeout(const Duration(seconds: 30))
        .whenComplete(() => reader.bookMapChanges.removeListener(listener));
  }

  /// The page that the session's pager shows.
  LaidPage shownPage(ReaderSession reader) => reader.pager!.shown.value!.page;

  /// Runs [step] on [reader], then saves and checks the session.
  Future<LaidPage> after(
    ReaderSession reader,
    Future<void> Function() step,
  ) async {
    await step();
    await reader.flush();
    reader.checkInvariants();
    return shownPage(reader);
  }

  final made = showcaseBooks();
  final places = fixture('epubjs-places.json')['books'] as Map;
  Publication showcase(String name) => Publication.admit(made[name]!);

  group('places that the WebView reader saved', () {
    for (final MapEntry(key: name as String, value: record as Map)
        in places.entries) {
      final sections = (record['sections'] as Map).cast<String, Map>();

      test('every page start that epub.js saved in $name reopens through the '
          'session on a page whose first line holds it, and the store gets '
          'no changed record', () async {
        final publication = showcase(name);
        expect(publication.identity, record['identity']);
        final document = EpubDocument(publication);
        var opened = 0;
        for (final size in recordedSizes) {
          for (final MapEntry(key: key, value: section) in sections.entries) {
            final index = int.parse(key);
            final resource = section['resource'] as String;
            final dom = await domOf(publication, index);
            for (final saved in (section['$size'] as List).cast<Map>()) {
              final where = '$name $size px section $index ${saved['cfi']}';
              final location = {
                'cfi': saved['cfi'],
                'resource': resource,
                'quote': saved['quote'],
                'progress': saved['progress'],
              };
              final anchor = anchorOf(document, location);
              final stored = snapshot(
                resumes: [anchor],
                bookmarks: [bookmarkAt('mark', anchor)],
                fontSize: size,
              );
              store
                ..values[accountKey] = jsonDecode(jsonEncode(stored))
                ..saves.clear();

              final reader = await open(publication);
              final page = await present(reader, pageAt(size));

              final place = placeOf(dom, index, saved['cfi'] as String)!;
              expect(
                firstLineHolds(page, dom, place),
                isTrue,
                reason: '$where opened on another line',
              );
              expect(reader.message, isNull, reason: where);
              expect(reader.position!.anchor, anchor, reason: where);
              expect(
                reader.visibleAddress!.toJson(),
                ReadingLocation.fromJson(location).toJson(),
                reason: where,
              );
              expect(
                store.savedResumes,
                everyElement(stored['resumes'].single),
                reason: '$where saved a changed resume',
              );
              expect(store.savedBookmarks, isEmpty, reason: where);
              expect(store.values[accountKey], stored, reason: where);
              reader.dispose();
              sessions.remove(reader);
              opened++;
            }
          }
        }
        expect(opened, greaterThan(0));
      });

      test('every bookmark at a page start, a contents entry or a search hit '
          'that epub.js saved in $name opens through the session on a page '
          'that shows it, at its first line for a page start, and the bookmark '
          'stays as saved', () async {
        final publication = showcase(name);
        final document = EpubDocument(publication);
        final saved = <Map<String, dynamic>>[
          for (final section in sections.values)
            for (final page in (section['20'] as List).cast<Map>())
              {
                'cfi': page['cfi'],
                'resource': section['resource'],
                'quote': page['quote'],
                'progress': page['progress'],
              },
          for (final entry in (record['contents'] as List).cast<Map>())
            if (entry['error'] == null)
              {
                'cfi': entry['cfi'],
                'resource': entry['resource'],
                'quote': entry['quote'],
              },
          for (final search in (record['search'] as List).cast<Map>())
            for (final hit in (search['hits'] as List).cast<Map>())
              {
                'cfi': hit['cfi'],
                'resource': hit['resource'],
                'quote': hit['quote'],
              },
        ];
        final bookmarks = [
          for (final (index, location) in saved.indexed)
            bookmarkAt('mark-$index', anchorOf(document, location)),
        ];
        store.values[accountKey] = snapshot(bookmarks: bookmarks);

        final reader = await open(publication);
        await present(reader);
        for (final (index, location) in saved.indexed) {
          final where = '$name bookmark at ${location['cfi']}';
          final mark = reader.bookmarks.firstWhere(
            (mark) => mark.id == 'mark-$index',
          );
          final page = await after(
            reader,
            () => reader.restoreBookmark(mark.id),
          );
          final section = publication.spine.indexOf(
            location['resource'] as String,
          );
          final dom = await domOf(publication, section);
          final place = placeOf(dom, section, location['cfi'] as String)!;
          expect(
            location.containsKey('progress')
                ? firstLineHolds(page, dom, place)
                : holds(page, dom, place),
            isTrue,
            reason: where,
          );
          expect(reader.message, isNull, reason: where);
        }
        expect(store.savedBookmarks, isEmpty);
        expect(store.values[accountKey]!['bookmarks'], bookmarks);
      });
    }
  });

  group('reading a showcase book in the pager', () {
    test('a book opens at its start, and each turn shows the next page and '
        'saves its place', () async {
      final publication = showcase('showcase-frost');
      final reader = await open(publication);
      expect(reader.ready, isTrue, reason: 'The pager is attached at once.');
      final first = await present(reader);
      expect(first.section, 0);
      expect(first.start, const PageStart(0, 0));
      final opened = reader.visibleAddress! as EpubAddress;
      expect(opened.location.progress, 0);
      expect(store.savedResumes.last['anchor'], reader.position!.anchor);

      final second = await after(reader, () => reader.move(true));
      expect(identity(second), isNot(identity(first)));
      final turned = reader.visibleAddress! as EpubAddress;
      final dom = await domOf(publication, second.section);
      expect(
        placeOf(dom, second.section, turned.location.cfi),
        second.startPlace,
      );
      expect(store.savedResumes.last['anchor'], reader.position!.anchor);

      final back = await after(reader, () => reader.move(false));
      expect(identity(back), identity(first));
      expect(
        reader.visibleAddress!.toJson(),
        opened.toJson(),
        reason: 'The first page saves the same place again.',
      );
    });

    test('turns cross from section to section through the whole book and '
        'stop at its end', () async {
      final publication = showcase('showcase-frost');
      final reader = await open(publication);
      final seen = [await present(reader)];
      while (true) {
        final page = await after(reader, () => reader.move(true));
        if (identical(page, seen.last)) break;
        seen.add(page);
        expect(seen.length, lessThan(200));
      }
      expect(
        {for (final page in seen) page.section},
        {for (var i = 0; i < publication.spine.length; i++) i},
      );
    });

    test(
      'a bookmark saves the shown place and opens on its page again',
      () async {
        final publication = showcase('showcase-frost');
        final reader = await open(publication);
        await present(reader);
        final marked = await after(reader, () => reader.move(true));
        await reader.addBookmark(title: 'Grafts');
        final mark = reader.bookmarks.single;
        expect(mark.position.anchor, reader.position!.anchor);
        expect(
          store.savedBookmarks.single!['position'],
          encodeTextPosition(reader.position!),
        );

        await after(reader, () => reader.move(true));
        await after(reader, () => reader.move(true));
        final opened = await after(
          reader,
          () => reader.restoreBookmark(mark.id),
        );
        expect(identity(opened), identity(marked));
        expect(reader.position!.anchor, mark.position.anchor);
      },
    );

    test('search finds what epub.js found, and a hit opens on a page that '
        'shows it', () async {
      final publication = showcase('showcase-frost');
      final record = places['showcase-frost'] as Map;
      final reader = await open(publication);
      await present(reader);
      for (final search in (record['search'] as List).cast<Map>()) {
        await reader.search(search['query'] as String);
        reader.checkInvariants();
        expect(reader.searchError, search['error']);
        expect(
          [
            for (final hit in reader.hits)
              [
                hit.address.toJson()['cfi'],
                hit.address.resource,
                hit.address.quote,
              ],
          ],
          [
            for (final hit in (search['hits'] as List).cast<Map>())
              [hit['cfi'], hit['resource'], hit['quote']],
          ],
        );
        for (final hit in reader.hits) {
          final page = await after(reader, () => reader.openHit(hit));
          final section = publication.spine.indexOf(hit.address.resource);
          final dom = await domOf(publication, section);
          final place = placeOf(
            dom,
            section,
            hit.address.toJson()['cfi'] as String,
          )!;
          expect(holds(page, dom, place), isTrue);
        }
      }
    });

    test('a contents entry opens on the page that shows its target', () async {
      final publication = showcase('showcase-frost');
      final reader = await open(publication);
      await present(reader);
      expect(
        [for (final entry in reader.contents) (entry.title, entry.href)],
        [for (final entry in publication.contents) (entry.title, entry.href)],
      );
      for (final entry in reader.contents.reversed) {
        final page = await after(reader, () => reader.goToContents(entry.href));
        final section = publication.spine.indexOf('OEBPS/${entry.href}');
        final dom = await domOf(publication, section);
        expect(holds(page, dom, destination(dom, section, null)!), isTrue);
      }
    });

    test(
      'the chapter arrows go to the start of the next chapter and back',
      () async {
        final publication = showcase('showcase-frost');
        final reader = await open(publication);
        await present(reader);
        await mapped(reader);
        expect(reader.hasChapters, isTrue);

        final next = await after(reader, () => reader.moveChapter(true));
        expect((next.section, next.start), (1, const PageStart(0, 0)));
        final later = await after(reader, () => reader.move(true));
        expect(later.section, 1);
        final back = await after(reader, () => reader.moveChapter(false));
        expect((back.section, back.start), (1, const PageStart(0, 0)));
        final before = await after(reader, () => reader.moveChapter(false));
        expect((before.section, before.start), (0, const PageStart(0, 0)));
      },
    );
  });

  test('next chapter skips a chapter that starts in the middle of the shown '
      'page (t6-0cjf)', () async {
    final publication = Publication.admit(
      navBook(
        [
          '<h1 id="a">Alder</h1><p>The first chapter is short.</p>'
              '<h1 id="b">Birch</h1><p>The second starts on the same page.</p>'
              '${paragraphs(12)}<h1 id="c">Cedar</h1>${paragraphs(4)}',
        ],
        [
          ('Alder', 'text/s0.xhtml#a'),
          ('Birch', 'text/s0.xhtml#b'),
          ('Cedar', 'text/s0.xhtml#c'),
        ],
      ),
    );
    final reader = await open(publication);
    final first = await present(reader);
    await mapped(reader);
    final dom = await domOf(publication, 0);
    expect(holds(first, dom, destination(dom, 0, 'b')!), isTrue);
    expect(holds(first, dom, destination(dom, 0, 'c')!), isFalse);

    final next = await after(reader, () => reader.moveChapter(true));
    expect(holds(next, dom, destination(dom, 0, 'c')!), isTrue);
    expect(next.start.compareTo(first.start), greaterThan(0));
  });

  test('next chapter skips a chapter that starts in the middle of the first '
      'page after opening at a saved place (tc-klz2)', () async {
    final publication = Publication.admit(
      navBook(
        [
          '<h1 id="a">Alder</h1><p>The first chapter is short.</p>'
              '<h1 id="b">Birch</h1><p>The second starts on the same page.</p>'
              '${paragraphs(12)}<h1 id="c">Cedar</h1>${paragraphs(4)}',
        ],
        [
          ('Alder', 'text/s0.xhtml#a'),
          ('Birch', 'text/s0.xhtml#b'),
          ('Cedar', 'text/s0.xhtml#c'),
        ],
      ),
    );
    final first = await open(publication);
    await present(first);
    final anchor = first.position!.anchor;
    first.dispose();
    sessions.remove(first);
    store
      ..values[accountKey] = snapshot(resumes: [anchor])
      ..saves.clear();

    final reader = await open(publication);
    final page = await present(reader);
    await mapped(reader);
    final dom = await domOf(publication, 0);
    expect(
      (reader.visibleAddress! as EpubAddress).location.end,
      isNull,
      reason: 'The saved place is reported as saved, without its end.',
    );
    expect(holds(page, dom, destination(dom, 0, 'b')!), isTrue);

    final next = await after(reader, () => reader.moveChapter(true));
    expect(holds(next, dom, destination(dom, 0, 'c')!), isTrue);
    expect(next.start.compareTo(page.start), greaterThan(0));
  });

  group('places stay as saved', () {
    test(
      'a text size change keeps the shown place and adds no record',
      () async {
        final publication = showcase('showcase-frost');
        final reader = await open(publication);
        await present(reader);
        final page = await after(reader, () => reader.move(true));
        final address = reader.visibleAddress;
        final resumes = store.savedResumes.length;
        final bookmarks = store.savedBookmarks.length;

        await reader.setFontSize(26);
        const larger = PageSettings(
          width: 412,
          height: 671,
          fontSize: 26,
          night: false,
        );
        final relaid = await present(reader, larger);

        final dom = await domOf(publication, page.section);
        expect(holds(relaid, dom, page.startPlace!), isTrue);
        expect(reader.visibleAddress, same(address));
        expect(store.savedResumes, hasLength(resumes));
        expect(store.savedBookmarks, hasLength(bookmarks));
        expect(store.values[accountKey]!['fontSize'], 26);
      },
    );

    test('a place saved at each turn opens on the same page in a new '
        'session, and that open saves no changed record', () async {
      final publication = showcase('showcase-frost');
      final reader = await open(publication);
      final turns = [await present(reader)];
      final anchors = [reader.position!.anchor];
      while (true) {
        final page = await after(reader, () => reader.move(true));
        if (identical(page, turns.last)) break;
        turns.add(page);
        anchors.add(reader.position!.anchor);
      }
      reader.dispose();
      sessions.remove(reader);

      for (final (turn, page) in turns.indexed) {
        store
          ..values[accountKey] = snapshot(resumes: [anchors[turn]])
          ..saves.clear();
        final restarted = await open(publication);
        final reopened = await present(restarted);
        expect(identity(reopened), identity(page), reason: 'turn $turn');
        expect(
          store.savedResumes,
          everyElement(encodeTextPosition(positionAt(anchors[turn]))),
          reason: 'turn $turn',
        );
        restarted.dispose();
        sessions.remove(restarted);
      }
    });

    test('a saved place whose quote does not match opens the start, keeps '
        'its record, and gives way only to a move', () async {
      final publication = showcase('showcase-frost');
      final document = EpubDocument(publication);
      final record = places['showcase-frost'] as Map;
      final page =
          ((record['sections'] as Map)['1']['20'] as List).first as Map;
      final anchor = anchorOf(document, {
        'cfi': page['cfi'],
        'resource': 'OEBPS/chapter2.xhtml',
        'quote': 'Words that this book does not have at that place.',
        'progress': page['progress'],
      });
      final stored = snapshot(resumes: [anchor]);
      store.values[accountKey] = jsonDecode(jsonEncode(stored));

      final reader = await open(publication);
      final first = await present(reader);
      expect((first.section, first.start), (0, const PageStart(0, 0)));
      expect(
        reader.message,
        'The saved place does not match this text. Reading starts at the '
        'beginning.',
      );
      expect(reader.visibleAddress, isNull);
      expect(reader.position, isNull);
      expect(store.savedResumes, isEmpty);
      expect(store.values[accountKey], stored);

      await reader.setFontSize(24);
      await present(
        reader,
        const PageSettings(width: 412, height: 671, fontSize: 24, night: false),
      );
      expect(store.savedResumes, isEmpty);
      expect(store.values[accountKey]!['resumes'], stored['resumes']);

      await after(reader, () => reader.move(true));
      expect(store.savedResumes.single['anchor'], reader.position!.anchor);
      expect(
        (store.values[accountKey]!['resumes'] as List).single['anchor'],
        reader.position!.anchor,
      );
    });
  });

  group('the session owns the pager', () {
    test('a book without contents lists one chapter for each linear section, '
        'as the WebView reader did, and each opens its section', () async {
      final publication = Publication.admit(
        bookWithoutContents([
          (paragraphs(2, label: 'Opening'), null),
          (paragraphs(2, label: 'Aside'), 'no'),
          (paragraphs(2, label: 'Middle'), 'yes'),
          (paragraphs(2, label: 'Close'), null),
        ]),
      );
      expect(publication.contents, isEmpty);
      final reader = await open(publication);
      expect(
        [
          for (final entry in reader.contents)
            (entry.title, entry.href, entry.depth),
        ],
        [
          ('Chapter 1', 'text/s0.xhtml', 0),
          ('Chapter 2', 'text/s2.xhtml', 0),
          ('Chapter 3', 'text/s3.xhtml', 0),
        ],
      );
      await present(reader);
      for (final (entry, section) in [
        for (final (index, entry) in reader.contents.indexed)
          (entry, [0, 2, 3][index]),
      ].reversed) {
        final page = await after(reader, () => reader.goToContents(entry.href));
        expect((page.section, page.start), (section, const PageStart(0, 0)));
      }
    });

    test('widgets that follow the open book learn of the pager, and closing '
        'the book disposes it', () async {
      final reader = sessionOf(showcase('showcase-frost'));
      await reader.bind(account(), [bookOf(epubEdition)]);
      final seen = <EpubPager?>[];
      reader.documentChanges.addListener(() => seen.add(reader.pager));
      await reader.open(bookOf(epubEdition), epubEdition);
      final pager = reader.pager;
      expect(pager, isNotNull);
      expect(seen.last, same(pager));

      reader.closeView(reader.token);
      reader.checkInvariants();
      expect(reader.pager, isNull);
      expect(() => pager!.present(readerPage), throwsStateError);
    });
  });

  group('a MOBI book', () {
    final library = Platform.environment['BOOKFIN_MOBI_LIBRARY'];
    final skip = library == null || !File(library).existsSync()
        ? 'libmobi is not on this host: run the test in the dev shell, which '
              'sets BOOKFIN_MOBI_LIBRARY'
        : null;

    test('opens in the pager, turns, searches, opens a hit and its contents, '
        'and reopens at its saved place', () async {
      final folder = await Directory.systemTemp.createTemp('bookfin-mobi-');
      addTearDown(() => folder.delete(recursive: true));
      final mobi = await File('${folder.path}/original.mobi').writeAsBytes(
        await File('tool/research/readers/fixtures/pg11-kf8.mobi')
            .readAsBytes(),
      );
      final mobiFile = file('mobi');
      final edition = editionOf(mobiFile);
      downloads.files[mobiFile.key] = mobi.uri;

      final reader = await open(
        null,
        edition: edition,
        loadDocument: loadReadingDocument,
      );
      expect(reader.document!.format, 'mobi');
      expect(reader.pager, isNotNull);
      await present(reader);
      final turned = await after(reader, () => reader.move(true));
      final saved = reader.position!.anchor;

      await reader.search('Alice');
      expect(reader.hits, isNotEmpty);
      await after(reader, () => reader.openHit(reader.hits.last));
      if (reader.contents.isNotEmpty) {
        await after(
          reader,
          () => reader.goToContents(reader.contents.last.href),
        );
      }
      reader.dispose();
      sessions.remove(reader);

      store
        ..values[accountKey] = {
          'version': 1,
          'fontSize': 20,
          'resumes': [encodeTextPosition(positionAt(saved, edition))],
          'bookmarks': const [],
        }
        ..saves.clear();
      final restarted = await open(
        null,
        edition: edition,
        loadDocument: loadReadingDocument,
      );
      final reopened = await present(restarted);
      expect(identity(reopened), identity(turned));
      expect(
        store.savedResumes,
        everyElement(encodeTextPosition(positionAt(saved, edition))),
      );
    }, skip: skip);
  });
}
