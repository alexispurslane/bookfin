import 'dart:async';

import 'package:flutter/material.dart' hide TextPosition;

import '../catalog/book_cover.dart';
import '../catalog/glass.dart'
    show GlassSheetAction, confirmAction, showGlassSheet;
import '../catalog/library_view.dart' show BookRow, ShelfFilterChips;
import '../catalog/model.dart';
import '../catalog/shelf.dart' show ShelfFilter, bookMatches;
import '../foundation/derived_value.dart';
import '../foundation/theme.dart';
import '../foundation/time.dart';
import '../playback/playback.dart';
import '../playback/recent.dart';
import '../playback/records_screen.dart';
import '../playback/screen.dart';
import '../playback/timeline.dart';
import '../reader/document.dart'
    show ContentsEntry, EpubAddress, ReaderHit, ReadingLocation;
import '../reader/screen.dart';

// The development gallery shows the app's own leaf widgets with sample books
// and places, so that a change to a leaf shows here too. It has no catalog,
// Downloads or Playback. Each screen of the gallery is the controller of its
// leaves: it handles what they report by changing only sample state, the
// listening sample in _SamplePlayer and each screen's own State.

class DevelopmentGallery extends StatefulWidget {
  const DevelopmentGallery({super.key});

  @override
  State<DevelopmentGallery> createState() => _DevelopmentGalleryState();
}

class _DevelopmentGalleryState extends State<DevelopmentGallery> {
  /// The shown screen: 0 the library, 1 the player, 2 the reader.
  int _screen = 0;
  final _sample = _SamplePlayer(DateTime.now());

  @override
  void dispose() {
    _sample.dispose();
    super.dispose();
  }

  void _showPlayer() => setState(() => _screen = 1);

  void _open(Book book) {
    _sample.open(book);
    _showPlayer();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          children: [
            Text(
              'Development gallery · sample books and positions\nNo server connection, downloads, or audio',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 4,
              children: [
                for (final (index, label) in [
                  'Library',
                  'Player & history',
                  'Reader',
                ].indexed)
                  TextButton(
                    onPressed: () => setState(() => _screen = index),
                    style: TextButton.styleFrom(
                      backgroundColor: _screen == index
                          ? Theme.of(context).colorScheme.surfaceContainer
                          : null,
                    ),
                    child: Text(label),
                  ),
              ],
            ),
          ],
        ),
      ),
      Expanded(
        child: BookfinScreenStack(
          index: _screen,
          children: [
            _LibraryFixture(onOpen: _open),
            _PlayerFixture(sample: _sample, onOpen: _sample.open),
            const _ReaderFixture(),
          ],
        ),
      ),
      // As in the app, the mini player sits below every page but the player.
      if (_screen != 1)
        ValueListenableBuilder(
          valueListenable: _sample.book,
          builder: (context, book, _) => MiniPlayerCard(
            book: book,
            onOpen: _showPlayer,
            notice: _undoNotice(_sample),
            controls: [
              _playPause(_sample),
              _jump(_sample, forward: true, compact: true),
            ],
            progress: _sample.share,
          ),
        ),
    ],
  );
}

/// The length of every sample recording, in milliseconds: 3 h 28 min.
const _length = 12480000;

/// The sample chapters, the same for every sample recording.
final _chapters = [
  for (var index = 0; index < 12; index++)
    PlaybackChapter(
      'Chapter ${index + 1}',
      'sample',
      index * _length ~/ 12,
      index * _length ~/ 12,
    ),
];

/// The index in [_chapters] of the chapter that holds [position], in
/// milliseconds from the start.
int _chapterAt(int position) =>
    _chapters.lastIndexWhere((chapter) => chapter.milliseconds <= position);

/// A sample book whose first edition is its audiobook. With [ebook], it also
/// has an EPUB edition.
Book _sampleBook(
  String id,
  String title,
  String author, {
  String? series,
  bool ebook = false,
}) => Book(
  id: id,
  title: title,
  author: author,
  series: series,
  editions: [
    Edition(
      id: '$id-audio',
      kind: EditionKind.audio,
      label: 'Audiobook',
      files: [
        SourceFile(
          itemId: '$id-file',
          displayName: title,
          mediaSourceId: 'source',
          revision: '1',
          durationMs: _length,
          container: 'm4b',
          sizeBytes: null,
        ),
      ],
      memberIds: ['$id-file'],
    ),
    if (ebook)
      Edition(
        id: '$id-epub',
        kind: EditionKind.text,
        label: 'EPUB',
        files: [
          SourceFile(
            itemId: '$id-epub-file',
            displayName: title,
            mediaSourceId: 'source',
            revision: '1',
            durationMs: null,
            container: 'epub',
            sizeBytes: null,
          ),
        ],
        memberIds: ['$id-epub-file'],
      ),
  ],
);

final _timeMachine = _sampleBook(
  'time-machine',
  'The Time Machine',
  'H. G. Wells',
  ebook: true,
);
final _lostWorld = _sampleBook(
  'lost-world',
  'The Lost World',
  'Arthur Conan Doyle',
  series: 'Professor Challenger',
);
final _poisonBelt = _sampleBook(
  'poison-belt',
  'The Poison Belt',
  'Arthur Conan Doyle',
  series: 'Professor Challenger',
);

/// The sample library: each book, the availability line of its row, and
/// whether its audio is downloaded.
final _library = [
  (
    book: _timeMachine,
    detail: 'Audio downloaded · EPUB downloaded',
    downloaded: true,
  ),
  (book: _lostWorld, detail: 'Audio not downloaded', downloaded: false),
  (
    book: _poisonBelt,
    detail: 'Audio partial · 2 of 6 files · waiting for Wi-Fi',
    downloaded: false,
  ),
];

AudioPosition _place(Book book, int milliseconds) => AudioPosition(
  editionId: book.editions.first.id,
  sourceKey: book.editions.first.files.single.key,
  revision: '1',
  milliseconds: milliseconds,
);

/// The sample listening records of every sample book, newest first, as of
/// [now].
List<TimelineEntry> _sampleTimeline(DateTime now) {
  HistoryEvent<AudioPosition> event(
    String id,
    Duration ago,
    HistoryAction kind,
    Book book,
    int before,
    int after,
  ) => HistoryEvent(
    id: id,
    at: now.subtract(ago),
    kind: kind,
    before: _place(book, before),
    after: _place(book, after),
    bookTitle: book.title,
    editionLabel: 'Audiobook',
  );
  return [
    ActionEntry(
      event(
        'pause',
        const Duration(minutes: 12),
        HistoryAction.pause,
        _timeMachine,
        5234000,
        5234000,
      ),
    ),
    ActionEntry(
      event(
        'jump',
        const Duration(minutes: 25),
        HistoryAction.jump,
        _timeMachine,
        3729000,
        4320000,
      ),
    ),
    BookmarkEntry(
      Bookmark(
        id: 'eloi',
        position: _place(_timeMachine, 4800000),
        createdAt: now.subtract(const Duration(minutes: 40)),
        bookTitle: _timeMachine.title,
        editionLabel: 'Audiobook',
        title: 'The Eloi',
      ),
    ),
    ActionEntry(
      event(
        'chapter',
        const Duration(days: 1),
        HistoryAction.chapter,
        _poisonBelt,
        900000,
        1800000,
      ),
    ),
  ];
}

/// The gallery's stand-in for Playback: the open sample book, its place, and
/// the sample records, in memory. No audio plays and nothing is saved. Only
/// the gallery changes it, through its methods.
class _SamplePlayer {
  _SamplePlayer(DateTime now)
    : timeline = ValueNotifier(_sampleTimeline(now)),
      _listened = [
        (
          book: _poisonBelt,
          edition: _poisonBelt.editions.first,
          at: now.subtract(const Duration(days: 1)),
        ),
        (
          book: _lostWorld,
          edition: _lostWorld.editions.first,
          at: now.subtract(const Duration(days: 3)),
        ),
        (
          book: _timeMachine,
          edition: _timeMachine.editions.first,
          at: now.subtract(const Duration(days: 5)),
        ),
      ] {
    recent = ValueNotifier(_recentNow());
  }

  final book = ValueNotifier(_timeMachine);

  /// The place in the open book, in milliseconds from its start.
  final position = ValueNotifier(5234000);
  final playing = ValueNotifier(false);

  /// The place before the last move, which Undo returns to, or null when
  /// there is nothing to undo.
  final previous = ValueNotifier<int?>(null);

  /// The actions and bookmarks of every sample book, newest first.
  final ValueNotifier<List<TimelineEntry>> timeline;
  final status = ValueNotifier<PlaybackStatus>((
    message: null,
    saveFailed: true,
  ));
  final replacement = ValueNotifier<AudioReplacement?>(
    AudioReplacement(
      _timeMachine,
      _timeMachine.editions.first,
      _place(_timeMachine, 5234000),
    ),
  );

  /// Every sample book, newest listening first.
  final List<RecentListening> _listened;

  /// Every sample book, newest listening first, each with its saved place.
  /// A list of recent books leaves out the open book.
  late final ValueNotifier<List<RecentProgress>> recent;

  /// The saved place of each sample book that is not open, by book id.
  final _places = {_lostWorld.id: 0, _poisonBelt.id: 1800000};

  /// How far through the open sample book the place is, from 0 to 1.
  late final share = DerivedValue(position, () => position.value / _length);

  /// The saved place of [other], in milliseconds.
  int _placeOf(Book other) =>
      other.id == book.value.id ? position.value : _places[other.id] ?? 0;

  /// The bookmarks of the open book, where the position slider marks them.
  List<EditionBookmark> get bookmarks => [
    for (final entry in timeline.value)
      if (entry
          case BookmarkEntry(bookmark: final Bookmark<AudioPosition> bookmark)
          when bookmark.position.editionId == book.value.editions.first.id)
        (bookmark: bookmark, at: bookmark.position.milliseconds),
  ];

  List<RecentProgress> _recentNow() => [
    for (final entry in _listened)
      (
        entry: entry,
        progress: (elapsedMs: _placeOf(entry.book), totalMs: _length),
      ),
  ];

  /// Opens [next] at its saved place. The open book keeps its place.
  void open(Book next) {
    if (next.id == book.value.id) return;
    _places[book.value.id] = position.value;
    book.value = next;
    position.value = _places.remove(next.id) ?? 0;
    previous.value = null;
    recent.value = _recentNow();
  }

  /// Moves to [milliseconds] in the open book, and offers Undo.
  void move(int milliseconds) {
    previous.value = position.value;
    position.value = milliseconds.clamp(0, _length);
  }

  /// Opens the book of [place], then moves to it. The sample has listening
  /// places only.
  void goTo(Place place) {
    if (place is! AudioPosition) return;
    open(
      _library
          .map((entry) => entry.book)
          .firstWhere((book) => book.editions.first.id == place.editionId),
    );
    move(place.milliseconds);
  }

  void jump(bool forward) => move(position.value + (forward ? 30000 : -15000));

  void undo() {
    if (previous.value case final place?) position.value = place;
    previous.value = null;
  }

  void dismissUndo() => previous.value = null;

  void playPause() => playing.value = !playing.value;

  void startReplacement(AudioReplacement request) {
    replacement.value = null;
    move(0);
  }

  void retrySave() => status.value = (message: null, saveFailed: false);

  void delete(TimelineEntry entry) => timeline.value = [
    for (final kept in timeline.value)
      if (kept.id != entry.id) kept,
  ];

  void rename(Bookmark<AudioPosition> bookmark, String title, String note) =>
      timeline.value = [
        for (final entry in timeline.value)
          entry.id == bookmark.id
              ? BookmarkEntry(
                  Bookmark(
                    id: bookmark.id,
                    position: bookmark.position,
                    createdAt: bookmark.createdAt,
                    bookTitle: bookmark.bookTitle,
                    editionLabel: bookmark.editionLabel,
                    title: title,
                    note: note,
                  ),
                )
              : entry,
      ];

  void dispose() {
    for (final notifier in <ChangeNotifier>[
      book,
      position,
      playing,
      previous,
      timeline,
      status,
      replacement,
      recent,
    ]) {
      notifier.dispose();
    }
  }
}

Widget _playPause(_SamplePlayer sample, {bool large = false}) =>
    ValueListenableBuilder(
      valueListenable: sample.playing,
      builder: (context, playing, _) => PlayPauseButton(
        playing: playing,
        large: large,
        onPlayPause: sample.playPause,
      ),
    );

Widget _jump(
  _SamplePlayer sample, {
  required bool forward,
  bool compact = false,
}) => JumpButton(
  forward: forward,
  seconds: forward ? 30 : 15,
  compact: compact,
  onJump: sample.jump,
);

Widget _undoNotice(_SamplePlayer sample) => ValueListenableBuilder(
  valueListenable: sample.previous,
  builder: (context, previous, _) => previous == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: UndoNotice(
            unsaved: false,
            onUndo: sample.undo,
            onDismiss: sample.dismissUndo,
          ),
        ),
);

class _LibraryFixture extends StatefulWidget {
  const _LibraryFixture({required this.onOpen});

  /// Reports a tap on a book, which asks to open it in the player.
  final ValueChanged<Book> onOpen;

  @override
  State<_LibraryFixture> createState() => _LibraryFixtureState();
}

class _LibraryFixtureState extends State<_LibraryFixture> {
  ShelfFilter _filter = ShelfFilter.all;

  @override
  Widget build(BuildContext context) => ListView(
    key: const PageStorageKey('gallery-library'),
    padding: const EdgeInsets.fromLTRB(18, 20, 18, 24),
    children: [
      Text(
        'A little further\ninto the story.',
        style: Theme.of(context).textTheme.displaySmall,
      ),
      const SizedBox(height: 20),
      ShelfFilterChips(
        selected: _filter,
        onChanged: (filter) => setState(() => _filter = filter),
      ),
      const SizedBox(height: 8),
      AnimatedSize(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 360),
        alignment: Alignment.topCenter,
        curve: Curves.easeOutCubic,
        child: Column(
          children: [
            for (final (:book, :detail, :downloaded) in _library)
              if (bookMatches(book, _filter, (_) => downloaded))
                BookRow(
                  cover: BookCover.book(
                    book,
                    downloaded: downloaded,
                    showText: false,
                  ),
                  title: book.title,
                  author: book.author,
                  detail: detail,
                  onTap: () => widget.onOpen(book),
                ),
          ],
        ),
      ),
    ],
  );
}

class _PlayerFixture extends StatelessWidget {
  const _PlayerFixture({required this.sample, required this.onOpen});

  final _SamplePlayer sample;

  /// Reports a tap on a recent book, which asks to open it.
  final ValueChanged<Book> onOpen;

  Future<void> _confirmDelete(BuildContext context, TimelineEntry entry) async {
    if (await confirmAction(
      context,
      title: entry is BookmarkEntry
          ? 'Delete bookmark?'
          : 'Delete history action?',
      message: 'Remove this sample entry from the gallery.',
      action: 'Delete',
    )) {
      sample.delete(entry);
    }
  }

  /// Shows the sample chapters. A chosen chapter moves the sample there.
  Future<void> _chooseChapter(BuildContext context) {
    final position = sample.position.value;
    return showChapters(
      context,
      chapters: _chapters,
      current: _chapterAt(position),
      position: position,
      onChapter: (chapter) => sample.move(chapter.milliseconds),
    );
  }

  Future<void> _rename(
    BuildContext context,
    Bookmark<AudioPosition> bookmark,
  ) async {
    final edited = await showBookmarkEditor(
      context,
      heading: 'Edit bookmark',
      title: bookmark.title,
      note: bookmark.note,
      place: 'At ${audioTime(bookmark.position.milliseconds)}',
    );
    if (edited != null) sample.rename(bookmark, edited.title, edited.note);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      key: const PageStorageKey('gallery-player'),
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      children: [
        const Center(child: SectionLabel('NOW LISTENING · SAMPLE')),
        const SizedBox(height: 24),
        ValueListenableBuilder(
          valueListenable: sample.book,
          builder: (context, book, _) => Column(
            children: [
              SizedBox(width: 176, child: BookCover.book(book)),
              const SizedBox(height: 20),
              Text(
                book.title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge,
              ),
              Text(
                book.author,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
        ValueListenableBuilder(
          valueListenable: sample.position,
          builder: (context, position, _) {
            final chapter = _chapterAt(position);
            return Center(
              child: TextButton(
                onPressed: () => unawaited(_chooseChapter(context)),
                child: Text(
                  '${_chapters[chapter].name} · ${chapter + 1} of ${_chapters.length}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            );
          },
        ),
        ValueListenableBuilder(
          valueListenable: sample.status,
          builder: (context, status, _) =>
              RecordSaveNotice(status: status, onRetrySave: sample.retrySave),
        ),
        ValueListenableBuilder(
          valueListenable: sample.replacement,
          builder: (context, request, _) => request == null
              ? const SizedBox.shrink()
              : ReplacementOffer(
                  request: request,
                  onStartReplacement: sample.startReplacement,
                ),
        ),
        const SizedBox(height: 10),
        ListenableBuilder(
          listenable: Listenable.merge([
            sample.position,
            sample.timeline,
            sample.book,
          ]),
          builder: (context, _) {
            final position = sample.position.value;
            return PositionSlider(
              position: position,
              total: _length,
              chapters: _chapters,
              chapterIndex: _chapterAt(position),
              bookmarks: sample.bookmarks,
              onSeekStart: () {},
              onSeekEnd: (milliseconds) async => sample.move(milliseconds),
            );
          },
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _jump(sample, forward: false),
            const SizedBox(width: 30),
            _playPause(sample, large: true),
            const SizedBox(width: 30),
            _jump(sample, forward: true),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(height: UndoNotice.height + 8, child: _undoNotice(sample)),
        const SizedBox(height: 12),
        const SectionLabel('HISTORY'),
        SizedBox(
          height: 320,
          child: HistoryTimeline(
            entries: sample.timeline,
            describe: (place) => switch (place) {
              AudioPosition(:final milliseconds) => (
                short: audioTime(milliseconds),
                chapter: null,
                quote: null,
                along: AlongAudio(milliseconds),
              ),
              TextPosition() => (
                short: '',
                chapter: null,
                quote: null,
                along: null,
              ),
            },
            showBooks: true,
            onGoBack: (event) => sample.goTo(event.before),
            onGoTo: (entry) => sample.goTo(switch (entry) {
              ActionEntry(:final event) => event.after,
              BookmarkEntry(:final bookmark) => bookmark.position,
            }),
            onRename: (bookmark) {
              if (bookmark is Bookmark<AudioPosition>) {
                unawaited(_rename(context, bookmark));
              }
            },
            onDelete: (entry) => unawaited(_confirmDelete(context, entry)),
          ),
        ),
        const SizedBox(height: 18),
        ValueListenableBuilder(
          valueListenable: sample.book,
          builder: (context, open, _) => RecentListeningList(
            recent: sample.recent,
            open: open,
            onResume: (entry) => onOpen(entry.book),
          ),
        ),
      ],
    );
  }
}

/// The sample chapters of the reader: the heading number, the title and the
/// contents entry.
const _readerChapters = [
  ('I', 'The Time Traveller', ContentsEntry('I · The Time Traveller', 'i')),
  ('II', 'The Machine', ContentsEntry('II · The Machine', 'ii')),
  (
    'III',
    'The Time Traveller Returns',
    ContentsEntry('III · The Time Traveller Returns', 'iii'),
  ),
];

const _paragraphs = [
  'The Time Traveller (for so it will be convenient to speak of him) was expounding a recondite matter to us. His grey eyes shone and twinkled, and his usually pale face was flushed and animated.',
  'The fire burned brightly, and the soft radiance of the incandescent lights in the lilies of silver caught the bubbles that flashed and passed in our glasses.',
];

class _ReaderFixture extends StatefulWidget {
  const _ReaderFixture();

  @override
  State<_ReaderFixture> createState() => _ReaderFixtureState();
}

class _ReaderFixtureState extends State<_ReaderFixture> {
  /// The sample text size. The settings sheet follows it while it is open.
  final _fontSize = ValueNotifier<double>(19);

  /// Whether the sample page shows the night reading theme, or null while it
  /// follows the app's theme.
  final _night = ValueNotifier<bool?>(null);

  /// The index in [_readerChapters] of the shown chapter.
  int _chapter = 0;
  int _nextBookmark = 0;
  final _bookmarks = ValueNotifier<List<Bookmark<TextPosition>>>([]);
  final _hits = ValueNotifier<List<ReaderHit>>([]);
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    _fontSize.dispose();
    _night.dispose();
    _bookmarks.dispose();
    _hits.dispose();
    super.dispose();
  }

  /// Shows the panel that [builder] builds on a glass sheet under [title]
  /// and its [action], if any, as the reader does.
  Future<void> _sheet(
    WidgetBuilder builder, {
    String? title,
    GlassSheetAction? action,
  }) => showGlassSheet<void>(
    context,
    title: title,
    action: action,
    isScrollControlled: true,
    builder: builder,
  );

  /// Shows the start of the chapter whose contents entry is [href].
  void _showChapter(String href) {
    setState(
      () => _chapter = _readerChapters.indexWhere(
        (chapter) => chapter.$3.href == href,
      ),
    );
    _scroll.jumpTo(0);
  }

  void _openContents() => unawaited(
    _sheet(
      (sheet) => ValueListenableBuilder(
        valueListenable: _bookmarks,
        builder: (_, bookmarks, _) => ReaderContentsPanel(
          contents: [for (final chapter in _readerChapters) chapter.$3],
          onContents: (href) {
            Navigator.pop(sheet);
            _showChapter(href);
          },
          bookmarks: bookmarks,
          onRestore: (bookmark) {
            Navigator.pop(sheet);
            _showChapter(bookmark.position.anchor);
          },
          onEdit: (bookmark) => unawaited(_editBookmark(bookmark)),
          onDelete: (bookmark) => unawaited(_deleteBookmark(bookmark)),
        ),
      ),
    ),
  );

  /// Whether the sample page shows the night theme.
  bool get _isNight =>
      _night.value ?? Theme.of(context).brightness == Brightness.dark;

  void _openSettings() => unawaited(
    _sheet(
      (sheet) => ListenableBuilder(
        listenable: Listenable.merge([_fontSize, _night]),
        builder: (_, _) => ReaderSettingsPanel(
          fontSize: _fontSize.value,
          onSmaller: _fontSize.value > 15 ? () => _fontSize.value -= 2 : null,
          onLarger: _fontSize.value < 29 ? () => _fontSize.value += 2 : null,
          night: _isNight,
          onNightChanged: (night) => _night.value = night,
        ),
      ),
      title: 'Reading settings',
    ),
  );

  void _search(String query) {
    final needle = query.trim().toLowerCase();
    _hits.value = [
      for (final (index, paragraph) in _paragraphs.indexed)
        if (needle.isNotEmpty && paragraph.toLowerCase().contains(needle))
          ReaderHit(
            EpubAddress(
              ReadingLocation(
                'sample-$index',
                'sample.xhtml',
                paragraph.substring(0, 40),
              ),
            ),
            paragraph,
          ),
    ];
  }

  Future<void> _openSearch() async {
    await _sheet(
      (sheet) => ValueListenableBuilder(
        valueListenable: _hits,
        builder: (_, hits, _) => ReaderSearchPanel(
          searching: false,
          hits: hits,
          error: null,
          onSearch: _search,
          onOpenHit: (_) => Navigator.pop(sheet),
        ),
      ),
      title: 'Search',
      action: GlassSheetAction(
        'Close',
        icon: Icons.close_rounded,
        onPressed: () {},
      ),
    );
    _hits.value = [];
  }

  void _addBookmark() => _bookmarks.value = [
    ..._bookmarks.value,
    Bookmark(
      id: 'sample-${_nextBookmark++}',
      position: TextPosition(
        editionId: 'sample-epub',
        sourceKey: 'sample.epub',
        revision: '1',
        anchor: _readerChapters[_chapter].$3.href,
      ),
      createdAt: DateTime.now(),
    ),
  ];

  Future<void> _editBookmark(Bookmark<TextPosition> bookmark) async {
    final edited = await showBookmarkEditor(
      context,
      heading: 'Edit reading bookmark',
      title: bookmark.title,
      note: bookmark.note,
      place: 'Saved ${dayAndTime(context, bookmark.createdAt)}',
    );
    if (edited == null) return;
    _bookmarks.value = [
      for (final kept in _bookmarks.value)
        kept.id == bookmark.id
            ? Bookmark(
                id: kept.id,
                position: kept.position,
                createdAt: kept.createdAt,
                title: edited.title,
                note: edited.note,
              )
            : kept,
    ];
  }

  Future<void> _deleteBookmark(Bookmark<TextPosition> bookmark) async {
    if (await confirmAction(
      context,
      title: 'Delete reading bookmark?',
      message: 'Remove this sample bookmark from the gallery.',
      action: 'Delete',
    )) {
      _bookmarks.value = [
        for (final kept in _bookmarks.value)
          if (kept.id != bookmark.id) kept,
      ];
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_fontSize, _night]),
    builder: (context, _) => _themed(context),
  );

  Widget _themed(BuildContext context) {
    final app = Theme.of(context);
    final night = _isNight;
    final theme = night == (app.brightness == Brightness.dark)
        ? app
        : bookfinTheme(night ? Brightness.dark : Brightness.light);
    return Theme(
      data: theme,
      child: Builder(
        builder: (context) => Material(
          color: theme.colorScheme.surface,
          child: _page(context, night),
        ),
      ),
    );
  }

  Widget _page(BuildContext context, bool night) {
    final (number, title, _) = _readerChapters[_chapter];
    final text = TextStyle(
      fontFamily: 'Source Serif 4',
      fontFamilyFallback: const ['Noto Serif'],
      fontSize: _fontSize.value,
      height: 1.85,
    );
    return ListView(
      key: const PageStorageKey('gallery-reader'),
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      children: [
        Text(
          'THE TIME MACHINE · SAMPLE EPUB',
          style: Theme.of(context).textTheme.labelSmall,
        ),
        const SizedBox(height: 32),
        Text('CHAPTER $number', style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 17),
        Text(title, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 28),
        for (final paragraph in _paragraphs) ...[
          Text(paragraph, style: text),
          const SizedBox(height: 20),
        ],
        const SizedBox(height: 8),
        ReaderDock(
          bar: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: ProgressLine(value: (_chapter + 1) / 12),
          ),
          tools: ReaderTools(
            onContents: _openContents,
            onSearch: () => unawaited(_openSearch()),
            onSettings: _openSettings,
            onBookmark: _addBookmark,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Sample chapters · no ebook file is open\nText size, theme and scroll stay in this gallery session.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
