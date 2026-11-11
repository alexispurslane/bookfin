// Crossings finds where a place of one edition lands in the other medium's
// edition of the same book. It keeps the text outlines that it measures
// between launches, and the alignments that it derives. It reads records
// and files, and writes no personal record.
import 'dart:convert';

import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/crossings/alignment.dart';
import 'package:bookfin/crossings/crossings.dart';
import 'package:bookfin/reader/text_outline.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Two files of a recording: chapters 1 and 2 in the first, 130 s long,
/// and chapter 3 in the second, 300 s long. Every chapter reads at 10
/// characters a second against [book].
const _discOne = SourceFile(
  itemId: 'one',
  displayName: 'Disc one',
  mediaSourceId: 'm1',
  revision: 'a1',
  durationMs: 130000,
  container: 'mp3',
  sizeBytes: 1,
  chapters: [
    AudioChapter('Opening Credits', 0),
    AudioChapter('Chapter 1', 30000),
  ],
);
const _discTwo = SourceFile(
  itemId: 'two',
  displayName: 'Disc two',
  mediaSourceId: 'm2',
  revision: 'a2',
  durationMs: 300000,
  container: 'mp3',
  sizeBytes: 1,
  chapters: [AudioChapter('Chapter 2', 0), AudioChapter('Chapter 3', 200000)],
);
const audio = Edition(
  id: 'audio',
  kind: EditionKind.audio,
  label: 'Narrator',
  files: [_discOne, _discTwo],
  memberIds: ['one:m1', 'two:m2'],
);

Edition ebookEdition({String revision = 't1'}) => Edition(
  id: 'ebook',
  kind: EditionKind.text,
  label: 'EPUB',
  files: [
    SourceFile(
      itemId: 'book',
      displayName: 'Book',
      mediaSourceId: 'original',
      revision: revision,
      durationMs: null,
      container: 'epub',
      sizeBytes: 1,
    ),
  ],
  memberIds: const ['book'],
);

/// Front matter of 1000 characters, then chapters I to III, in two
/// sections of 2500 characters each.
final book = TextOutline(
  parts: const [
    (path: 'OPS/a.xhtml', characters: 2500),
    (path: 'OPS/b.xhtml', characters: 2500),
  ],
  entries: const [
    (title: 'Title page', depth: 0, start: 0),
    (title: 'I', depth: 0, start: 1000),
    (title: 'II', depth: 0, start: 2000),
    (title: 'III', depth: 0, start: 4000),
  ],
);

/// A reading place of [ebookEdition] in section [resource] at [progress].
TextPosition reading(String resource, double progress, {String rev = 't1'}) =>
    TextPosition(
      editionId: 'ebook',
      sourceKey: 'book:original',
      revision: rev,
      anchor: jsonEncode({
        'version': 1,
        'cfi': 'epubcfi(/6/4!/4/2/1:0)',
        'resource': resource,
        'quote': 'Words.',
        'progress': progress,
      }),
    );

/// A listening place of [audio] in [file] at [milliseconds] into the file.
AudioPosition listening(SourceFile file, int milliseconds) => AudioPosition(
  editionId: 'audio',
  sourceKey: file.key,
  revision: file.revision,
  milliseconds: milliseconds,
);

/// Kept outlines in memory, by key.
class MemoryOutlines implements OutlineStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

void main() {
  late MemoryOutlines store;
  late ValueNotifier<int> downloads;
  late int measured;
  late int hops;
  TextOutline? download;
  late bool unsupported;
  late bool unreadable;
  late int failingHops;
  final made = <Crossings>[];

  setUp(() {
    store = MemoryOutlines();
    downloads = ValueNotifier(0);
    measured = 0;
    hops = 0;
    download = book;
    unsupported = false;
    unreadable = false;
    failingHops = 0;
  });
  tearDown(() {
    for (final crossings in made) {
      crossings.dispose();
    }
    made.clear();
  });

  Crossings crossings() {
    final made_ = Crossings(
      store: store,
      measure: (text) async {
        measured++;
        if (unsupported) throw UnsupportedError('A PDF has no outline yet.');
        if (unreadable) throw const FormatException('A broken EPUB.');
        return download;
      },
      downloads: downloads,
      hop: <M, R>(work, input) async {
        hops++;
        if (failingHops > 0) {
          failingHops--;
          throw StateError('A bug in the alignment.');
        }
        return work(input);
      },
    );
    made.add(made_);
    return made_;
  }

  test('a listening place lands at the same share of its matched chapter '
      'in the ebook', () async {
    final found = await crossings().landing(
      listening(_discTwo, 50000),
      from: audio,
      into: ebookEdition(),
    );

    // 50 s into chapter 2's 200 s: a quarter of its 2000 characters, at
    // 2500, the start of the second section.
    expect(found, isA<TextLanding>());
    final landing = found as TextLanding;
    expect(landing.place, (part: 1, progress: 0.0));
    expect(landing.matchedBy, MatchedBy.chapters);
    expect(landing.from.milliseconds, 50000);
  });

  test('a landing in the ebook says how far through the book it lies and '
      'which contents entry holds it, so the reader can name it before it '
      'measures the book', () async {
    final found = await crossings().landing(
      listening(_discTwo, 150000),
      from: audio,
      into: ebookEdition(),
    );

    // 150 s into chapter 2's 200 s: three quarters of its 2000 characters,
    // at 3500 of the book's 5000.
    final landing = found as TextLanding;
    expect(landing.share, closeTo(.7, 1e-9));
    expect(landing.chapter, 'II');
  });

  test('a reading place lands at the same share of its matched chapter in '
      'the recording, in the file that holds it', () async {
    final found = await crossings().landing(
      reading('OPS/b.xhtml', .2),
      from: ebookEdition(),
      into: audio,
    );

    // 3000 characters: half of chapter 2, 100 s into the second file.
    final landing = found as AudioLanding;
    expect(landing.place.sourceKey, 'two:m2');
    expect(landing.place.revision, 'a2');
    expect(landing.place.milliseconds, 100000);
    expect(landing.place.fits(audio), isTrue);
  });

  test('a place more than one page outside every matched chapter has no '
      'landing', () async {
    final found = await crossings().landing(
      reading('OPS/a.xhtml', 0),
      from: ebookEdition(),
      into: audio,
    );

    expect((found as NoLanding).reason, Refusal.outsideMatches);
  });

  test('chapters that do not match give the matcher\'s reason', () async {
    download = TextOutline(
      parts: const [(path: 'OPS/a.xhtml', characters: 5000)],
      entries: const [
        (title: 'Economy', depth: 0, start: 0),
        (title: 'Reading', depth: 0, start: 2500),
      ],
    );

    final found = await crossings().landing(
      listening(_discOne, 40000),
      from: audio,
      into: ebookEdition(),
    );

    expect((found as NoLanding).reason, Refusal.fewMatches);
  });

  test('an ebook that this phone never downloaded has no landing', () async {
    download = null;

    final found = await crossings().landing(
      listening(_discOne, 40000),
      from: audio,
      into: ebookEdition(),
    );

    expect((found as NoLanding).reason, Refusal.noOutline);
  });

  test('an ebook whose format Bookfin cannot measure yet has no landing, '
      'and says so', () async {
    unsupported = true;

    final found = await crossings().landing(
      listening(_discOne, 40000),
      from: audio,
      into: ebookEdition(),
    );

    expect((found as NoLanding).reason, Refusal.unsupportedFormat);
  });

  test(
    'an ebook that Bookfin cannot read has no landing, and says so',
    () async {
      unreadable = true;

      final found = await crossings().landing(
        listening(_discOne, 40000),
        from: audio,
        into: ebookEdition(),
      );

      expect((found as NoLanding).reason, Refusal.unreadable);
    },
  );

  test('a recording whose files change order aligns again', () async {
    final source = crossings();
    await source.landing(
      listening(_discOne, 40000),
      from: audio,
      into: ebookEdition(),
    );
    const reordered = Edition(
      id: 'audio',
      kind: EditionKind.audio,
      label: 'Narrator',
      files: [_discTwo, _discOne],
      memberIds: ['two:m2', 'one:m1'],
    );

    await source.landing(
      listening(_discOne, 40000),
      from: reordered,
      into: ebookEdition(),
    );

    expect(hops, 2);
    source.checkInvariants();
  });

  test('an alignment that fails is not kept, so a later request tries '
      'again', () async {
    final source = crossings();
    failingHops = 1;

    await expectLater(
      source.landing(
        listening(_discOne, 40000),
        from: audio,
        into: ebookEdition(),
      ),
      throwsStateError,
    );
    final found = await source.landing(
      listening(_discOne, 40000),
      from: audio,
      into: ebookEdition(),
    );

    expect(found, isA<TextLanding>());
    source.checkInvariants();
  });

  test('two recordings of one ebook measure the ebook once', () async {
    final source = crossings();
    const other = Edition(
      id: 'other audio',
      kind: EditionKind.audio,
      label: 'Another narrator',
      files: [_discOne, _discTwo],
      memberIds: ['one:m1', 'two:m2'],
    );

    await Future.wait([
      source.landing(
        listening(_discOne, 40000),
        from: audio,
        into: ebookEdition(),
      ),
      source.landing(
        AudioPosition(
          editionId: other.id,
          sourceKey: _discOne.key,
          revision: _discOne.revision,
          milliseconds: 40000,
        ),
        from: other,
        into: ebookEdition(),
      ),
    ]);

    expect(measured, 1);
    source.checkInvariants();
  });

  test('prepare aligns a pair in the background, so its landings are '
      'known at once', () async {
    final source = crossings();

    source.prepare(from: ebookEdition(), into: audio);
    await pumpEventQueue();

    expect(hops, 1);
    expect(
      source.landingNow(
        listening(_discOne, 40000),
        from: audio,
        into: ebookEdition(),
      ),
      isA<TextLanding>(),
    );
  });

  test(
    'an ebook that downloads later maps once Downloads reports it',
    () async {
      download = null;
      final source = crossings();
      await source.landing(
        listening(_discOne, 40000),
        from: audio,
        into: ebookEdition(),
      );

      download = book;
      downloads.value++;
      final found = await source.landing(
        listening(_discOne, 40000),
        from: audio,
        into: ebookEdition(),
      );

      expect(found, isA<TextLanding>());
    },
  );

  test('a measured outline is kept, so a later launch maps without the '
      'download', () async {
    await crossings().landing(
      listening(_discOne, 40000),
      from: audio,
      into: ebookEdition(),
    );
    download = null;

    final found = await crossings().landing(
      listening(_discOne, 40000),
      from: audio,
      into: ebookEdition(),
    );

    expect(found, isA<TextLanding>());
    expect(measured, 1);
  });

  test(
    'a kept outline of an older revision of the ebook is not used',
    () async {
      await crossings().landing(
        listening(_discOne, 40000),
        from: audio,
        into: ebookEdition(),
      );
      download = null;

      final found = await crossings().landing(
        listening(_discOne, 40000),
        from: audio,
        into: ebookEdition(revision: 't2'),
      );

      expect((found as NoLanding).reason, Refusal.noOutline);
    },
  );

  test('an unreadable kept outline is measured again', () async {
    await crossings().landing(
      listening(_discOne, 40000),
      from: audio,
      into: ebookEdition(),
    );
    for (final key in store.values.keys) {
      store.values[key] = '{"broken';
    }

    final found = await crossings().landing(
      listening(_discOne, 40000),
      from: audio,
      into: ebookEdition(),
    );

    expect(found, isA<TextLanding>());
    expect(measured, 2);
  });

  test(
    'a pair of editions aligns once, in one hop to another isolate',
    () async {
      final source = crossings();
      await source.landing(
        listening(_discOne, 40000),
        from: audio,
        into: ebookEdition(),
      );
      await source.landing(
        reading('OPS/b.xhtml', .2),
        from: ebookEdition(),
        into: audio,
      );

      expect(measured, 1);
      expect(hops, 1);
      source.checkInvariants();
    },
  );

  test('a landing that is not known yet starts the alignment, and the '
      'landing shows once it arrives', () async {
    final source = crossings();
    final place = listening(_discOne, 40000);
    var changed = 0;
    source.changes.addListener(() => changed++);

    expect(source.landingNow(place, from: audio, into: ebookEdition()), isNull);
    await pumpEventQueue();

    expect(changed, 1);
    expect(
      source.landingNow(place, from: audio, into: ebookEdition()),
      isA<TextLanding>(),
    );
  });
}
