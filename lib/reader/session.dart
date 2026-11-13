import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../catalog/jellyfin.dart';
import '../catalog/model.dart';
import '../crossings/crossings.dart' show TextLanding;
import '../downloads/downloads.dart';
import '../foundation/time.dart' show roundEstimate;
import '../playback/playback.dart';
import '../playback/record_writer.dart';
import 'book_map.dart';
import 'contents.dart';
import 'document.dart';
import 'epub/kept_page.dart';
import 'epub/pager.dart';
import 'epub/publication.dart';
import 'kept_pages.dart';
import 'page_previews.dart';
import 'pdf.dart';
import 'place_words.dart';
import 'last_page_settings.dart';
import 'reading_speed.dart';
import 'survey_files.dart';

typedef PublicationLoader = Future<Publication> Function(VerifiedFile file);
typedef DocumentLoader = Future<ReaderDocument> Function(
  VerifiedFile file,
  SourceFile source,
);
typedef VisibleLocation = ReadingLocation;

/// The estimated reading time left in the chapter and in the book.
typedef TimeLeft = ({Duration chapter, Duration book});

/// The owner of each account's saved reading records, as [ReaderSession]
/// uses it.
abstract class ReadingStore {
  /// The saved reading snapshot of [accountKey], or null when the account
  /// has none: `version`, `fontSize`, `resumes`, `bookmarks` and `history`,
  /// `sizesMainText` when it is true, legacy `trimMargins` when false,
  /// and `pdfBooks`, the PDF view and margin choice keyed by [Book.id].
  Future<Map<String, dynamic>?> read(String accountKey);

  /// Saves [changes] to the reading records of [accountKey].
  ///
  /// A record that [changes] does not name keeps its saved value. A named
  /// record that equals the value this writer last saved or accepted adds no
  /// sync action, so a retry can resend changes that were already saved.
  Future<void> saveReading(String accountKey, ReadingChanges changes);

  /// Records [value] as the snapshot that the writer of [accountKey] now
  /// shows, so later saves compare their records with it.
  void acceptSnapshot(String accountKey, Map<String, dynamic>? value) {}

  /// Where the saved place of [edition] in [accountKey] came from.
  Future<PlaceOrigin> origin(String accountKey, Edition edition) async =>
      (own: null, elsewhere: false, device: null);

  /// Whether this store found the saved records of [accountKey] damaged
  /// while this app ran, kept the damaged data aside, and started the
  /// account again from the records that it could read. A [read] of the
  /// account finds out.
  bool setAside(String accountKey) => false;
}

/// The reading records that one save changes.
///
/// A save carries the whole small [settings], but only the resumes,
/// bookmarks and moves that changed. One store transaction saves all of
/// them, so a move and the place where it ended save together.
class ReadingChanges {
  ReadingChanges(
    this.settings, {
    this.resumes = const [],
    this.bookmarks = const {},
    this.history = const {},
  });

  /// The version and the saved reading preferences.
  final Map<String, dynamic> settings;

  /// The changed resumes as JSON. A resume replaces the saved resume of the
  /// same edition, source and revision. Resumes are never deleted.
  final List<Map<String, dynamic>> resumes;

  /// The changed bookmarks as JSON, by id. A null value deletes it.
  final Map<String, Map<String, dynamic>?> bookmarks;

  /// The changed reading moves as JSON, by id. A null value deletes it.
  final Map<String, Map<String, dynamic>?> history;

  /// These changes followed by [later]: the later value of each record and
  /// the later settings win.
  ReadingChanges followedBy(ReadingChanges later) => ReadingChanges(
    later.settings,
    resumes: [
      for (final value in resumes)
        if (!later.resumes.any((next) => _samePlace(value, next))) value,
      ...later.resumes,
    ],
    bookmarks: {...bookmarks, ...later.bookmarks},
    history: {...history, ...later.history},
  );

  /// The reading snapshot that results when these changes apply to
  /// [snapshot]. A changed resume goes last, as the session orders its
  /// places. A changed bookmark or move keeps its place, a new one goes
  /// last, and a deleted one is removed.
  Map<String, dynamic> applyTo(Map<String, dynamic>? snapshot) {
    List<Map<String, dynamic>> byId(
      String collection,
      Map<String, Map<String, dynamic>?> changes,
    ) {
      final unplaced = Map.of(changes);
      return [
        for (final value in snapshot?[collection] as List? ?? const [])
          if (!unplaced.containsKey(value['id']))
            Map<String, dynamic>.from(value as Map)
          else
            ?unplaced.remove(value['id']),
        ...unplaced.values.nonNulls,
      ];
    }

    return {
      ...settings,
      'resumes': [
        for (final value in snapshot?['resumes'] as List? ?? const [])
          if (!resumes.any((next) => _samePlace(value as Map, next)))
            Map<String, dynamic>.from(value as Map),
        ...resumes,
      ],
      'bookmarks': byId('bookmarks', bookmarks),
      'history': byId('history', history),
    };
  }

  static bool _samePlace(
    Map<dynamic, dynamic> first,
    Map<dynamic, dynamic> second,
  ) =>
      first['edition'] == second['edition'] &&
      first['source'] == second['source'] &&
      first['revision'] == second['revision'];
}

/// The open book, its place, and the account's reading records.
///
/// The session notifies its own listeners once for each change of any part
/// of its visible state. Each part also has its own signal, so a widget can
/// follow only the part that it shows. A change that leaves every part as it
/// was, such as a finished write, notifies nothing.
///
/// Invariants, which [checkInvariants] checks:
/// - Without an account, no document is open and no records are held.
/// - An open document belongs to a current edition of the account.
/// - A navigator and a book map exist only while a document is open.
/// - A pager exists only while an EPUB or MOBI document is open, and every
///   such document that finished opening has one. The pager's own
///   invariants hold.
/// - A kept page exists only while a book opens or its pager shows no page
///   yet.
/// - The visible address and the saved position are both set or both
///   absent. The position fits the open document, and its saved form
///   restores the visible address.
/// - Every account whose save failed still has its changes pending.
/// - The Undo offer is a recorded move of the account.
/// - A pending move belongs to the open book.
/// - The move that a refinement can still name ends in the open edition.
/// - PDF preferences belong to the bound account and are keyed by book,
///   not edition. The open book's choices are derived from those preferences.
///
/// The session records each jump through the book as a reading move (see
/// [history]). A jump verb notes the pending move: its kind and the shown
/// place. The first place that the navigator then reports ends the move. A
/// move that ends on the page where it began records nothing, and a jump
/// that fails, or the open of another book, drops it. The move saves with
/// its new place in one change set, and becomes the Undo offer
/// ([undoOffer]). Page turns and changes of the text size are not moves.
///
/// A PDF page shows before its text arrives, and recognition of a scanned
/// page takes seconds. The navigator reports the page itself at once, so
/// the place and the move that ended there are saved while the text is on
/// its way. When the text names the place, the navigator reports it again
/// as a refinement ([refineAddress]). A refinement is the same place under
/// a better name: it records no move, and the move that ended there takes
/// the new name.
///
/// Each [open] starts a reading visit: the first place that the book shows
/// records an Opened entry there. If another device saved that place, and
/// this phone last showed another place, the entry is a move from this
/// phone's place, which names the device and becomes the Undo offer. A
/// History choice ([restoreHistory], [restoreBookmark]) that opens another
/// book's edition starts a visit the same way: when the chosen place is
/// not this phone's saved place in the edition, the visit starts with a
/// move of the choice's kind from the saved place, with Undo. Back
/// ([closeView]) and the open of another book end the visit with a Closed
/// entry at the shown place. The background records nothing. If Android
/// stops Bookfin, the visit has no Closed entry, and the saved place still
/// says where it ended.
class ReaderSession extends ChangeNotifier {
  ReaderSession({
    required this.downloads,
    required this.store,
    required this.load,
    this.loadDocument,
    this.speed,
    this.pageSettings,
    this.surveyStore,
    this.keptPages,
  }) {
    _signals = [
      _placeChanges = _Signal(() => (_visibleAddress, _position)),
      _documentChanges = _Signal(
        () => (
          _token,
          _book,
          _edition,
          _document,
          _navigator,
          _pager,
          _loading,
          _message,
          _contents,
          _initialAddress,
        ),
      ),
      _bookmarkChanges = _Signal(() => (_bookmarks, _edition, _recordsReady)),
      _historyChanges = _Signal(() => _history),
      _undoChanges = _Signal(() => undoOffer),
      _searchChanges = _Signal(() => (_searching, _hits, _searchError)),
      _fontSizeChanges = _Signal(() => (_fontSize, _sizesMainText)),
      _saveStatusChanges = _Signal(() => saveFailed),
      _pdfViewChanges = _Signal(() => pdfView),
      _trimMarginsChanges = _Signal(() => trimMargins),
      _bookMapChanges = _Signal(() => _bookMap),
      _timeLeftChanges = _Signal(() => timeLeft),
      _keptPageChanges = _Signal(() => (_keptPage, _readingKeptPage)),
    ];
    if (store case final RecordWriterHost host) {
      _unregisterWriter = host.registerWriter(
        account: () => _account,
        flush: flush,
        refresh: refreshPersonalRecords,
      );
    }
    speed?.charactersPerMinute.addListener(_emit);
  }
  VoidCallback? _unregisterWriter;
  final Downloads downloads;
  final ReadingStore store;
  final PublicationLoader load;
  final DocumentLoader? loadDocument;

  /// Makes the kept survey of an opened PDF (see [SurveyFiles]), or null
  /// when PDFs are not surveyed, as in tests of other things.
  final SurveyStoreOf? surveyStore;

  /// The kept page of each EPUB or MOBI download, or null when the session
  /// keeps none, as in tests of other things.
  ///
  /// An open at the saved place reads the page that was kept there, while
  /// the book loads, so the reader can draw it first ([keptPage]). The
  /// session keeps the shown page with its saved place at each [flush] and
  /// when the book closes.
  final KeptPages? keptPages;

  /// The kept page of the book that opens, from the read that its open
  /// started, until its pager shows a page. Null without one.
  KeptPage? get keptPage => _keptPage;
  KeptPage? _keptPage;

  /// Whether the open reads the kept page of the book. The reader shows the
  /// paper then, rather than a sign that the book loads.
  bool get readingKeptPage => _readingKeptPage;
  bool _readingKeptPage = false;

  /// Notifies when [keptPage] or [readingKeptPage] changes.
  Listenable get keptPageChanges => _keptPageChanges;

  /// The end of the last write of a kept page. Writes run one after another,
  /// so the newest page is kept last.
  Future<void> _keeping = Future.value();

  /// Whether the app is in the background, so that background work waits.
  var _suspended = false;

  /// Pauses the reader's background work while the app is in the
  /// background: the survey of the open PDF.
  void suspend() {
    _suspended = true;
    if (_document case final PdfBook book) book.survey.pause();
  }

  /// Goes on with the background work that [suspend] paused.
  void resume() {
    _suspended = false;
    if (!_recordsReady && _account != null) unawaited(_readAgain());
    if (_document case final PdfBook book) book.survey.resume();
  }

  /// Lends the download of [selected] to [read] while Downloads owns it and
  /// the catalog still holds the edition: the second argument of [read]
  /// says whether both still hold. Without the download, it gives [gone]
  /// or null. Work that started saves its result after the book closes, so
  /// whether the book is still open does not matter.
  Future<T?> _lend<T>(
    Edition selected,
    T gone,
    Future<T> Function(VerifiedFile original, bool Function() owned) read,
  ) async {
    bool available() => !_disposed && _current(selected);
    if (!available()) return null;
    bool Function() owned = () => true;
    return downloads.readLocalFile<T>(selected.files.single, (file) async {
      if (!available()) return gone;
      return read(file, () => owned() && available());
    }, onOwnership: (live) => owned = live);
  }

  /// Starts the survey of [book], the PDF of [selected], at the page that
  /// it opens at, when the session surveys PDFs. It keeps its results with
  /// the download.
  void _survey(PdfBook book, Edition selected) {
    final storeOf = surveyStore;
    if (storeOf == null) return;
    book.survey.start(
      storeOf(
        (use) => _lend<void>(selected, null, use),
        book: book.originalDigest,
        hop: book.hop,
      ),
      from: switch (_initialAddress) {
        PdfAddress(:final sourcePage) => sourcePage,
        _ => 1,
      },
    );
    if (_suspended) book.survey.pause();
  }

  /// The person's reading speed, which the pager's page turns feed and
  /// [timeLeft] reads. Without it, the session estimates no time.
  final ReadingSpeed? speed;

  /// The page settings of the last page that this phone showed, which each
  /// shown page of an EPUB updates. A pager starts to open its book with
  /// them before the reader's first layout presents the settings.
  final LastPageSettings? pageSettings;
  ReaderDocument? _document;
  ReaderDocument? get document => _document;
  Book? _book;
  Edition? _edition;
  TextPosition? _position;
  ReaderAddress? _visibleAddress;
  ReaderAddress? _initialAddress;
  Future<void> _closing = Future.value();
  bool _releaseFailed = false;
  int _token = 0;
  String? _message;
  bool _loading = false;
  bool _searching = false;
  double _fontSize = _defaultFontSize;
  bool _sizesMainText = false;
  String? _searchError;
  List<ReaderHit> _hits = const [];
  List<ContentsEntry> _contents = const [];
  Publication? get publication =>
      document is EpubDocument ? (document as EpubDocument).publication : null;
  Book? get book => _book;
  Edition? get edition => _edition;
  TextPosition? get position => _position;
  ReaderAddress? get visibleAddress => _visibleAddress;
  ReaderAddress? get initialAddress => _initialAddress;
  VisibleLocation? get visibleLocation => _visibleAddress is EpubAddress
      ? (_visibleAddress as EpubAddress).location
      : null;
  VisibleLocation? get initialLocation => _initialAddress is EpubAddress
      ? (_initialAddress as EpubAddress).location
      : null;
  int get token => _token;
  String? get message =>
      _message ??
      (_failedAccounts.contains(_account)
          ? 'Reading records were not saved. Free storage, then retry before closing.'
          : null);
  bool get loading => _loading;
  bool get searching => _searching;
  double get fontSize => _fontSize;

  /// Whether [fontSize] is the size of each book's main text
  /// (`PageSettings.sizesMainText`). It turns on with the first
  /// [setFontSize], and each book keeps its own type sizes until then.
  bool get sizesMainText => _sizesMainText;
  String? get searchError => _searchError;
  List<ReaderHit> get hits => _hits;
  List<ContentsEntry> get contents => _contents;
  DocumentNavigator? _navigator;

  /// The pager of the open EPUB or MOBI book, which the session creates when
  /// the book opens and disposes when it closes. The viewport shows its
  /// pages and presents the page settings to it. Null while no such book is
  /// open. It follows [documentChanges].
  EpubPager? get pager => _pager;
  EpubPager? _pager;
  String? _account;
  String? _credential;
  List<Book> _books = [];
  final List<TextPosition> _resumes = [];
  // NOTE: Replace this list on each change, never change it in place.
  // [bookmarkChanges] compares lists by identity.
  List<Bookmark<TextPosition>> _bookmarks = const [];

  /// The reading moves of the account, newest first.
  // NOTE: Replace this list on each change, never change it in place.
  // [historyChanges] compares lists by identity.
  List<HistoryEvent<TextPosition>> _history = const [];

  /// The move that [undoMove] takes back, or null.
  HistoryEvent<TextPosition>? _undo;

  /// The jump whose place has not shown yet, or null.
  _Move? _pending;

  /// The move that the last [acceptAddress] ended at the visible place, or
  /// null when that report ended none. [refineAddress] gives its end the
  /// place as the text names it.
  HistoryEvent<TextPosition>? _landed;

  /// The end of the last jump in the open book. Jumps run one after
  /// another. The open of another book drops the jumps that wait.
  Future<void> _jumps = Future.value();
  bool _disposed = false;
  bool _recordsReady = false;
  int _accountGeneration = 0;
  Future<void> _binding = Future.value();
  Future<void> _writes = Future.value();
  final _pendingWrites = <String, ReadingChanges>{};
  final _failedAccounts = <String>{};

  /// The record changes of each account that were made while its saved
  /// records were unread: the first read still runs, or it failed. They
  /// wait in memory, because a save carries the whole settings, and the
  /// settings of unread records are defaults that would replace the saved
  /// ones. [_readRecords] merges them into the records that it reads and
  /// then saves them, so a failed read costs no place (boo-y2sj).
  final _unreadChanges = <String, ReadingChanges>{};

  /// The notice while the records of the account are unread after a failed
  /// read. It ends when a later read opens them.
  static const _recordsUnread =
      'Reading records could not be opened. Existing records were kept. '
      'Bookfin keeps new places and saves them when the records open.';
  int _search = 0;
  int _recordRevision = 0;

  /// Notifies when the visible place changes: [visibleAddress],
  /// [visibleLocation] and [position]. A page turn notifies only this signal.
  Listenable get placeChanges => _placeChanges;

  /// Notifies when the open book changes: [book], [edition], [document],
  /// [publication], [ready], [loading], [token], [contents],
  /// [initialAddress] and the opening part of [message]. [message] also
  /// follows [saveStatusChanges].
  Listenable get documentChanges => _documentChanges;

  /// Notifies when [bookmarks] changes, which includes opening another
  /// edition and loading the account's records. [canBookmark] follows this
  /// signal and [placeChanges].
  Listenable get bookmarkChanges => _bookmarkChanges;

  /// The reading moves of the account in every edition, newest first. It
  /// follows the saved records, which the session reads at [bind] and at
  /// [refreshPersonalRecords].
  List<HistoryEvent<TextPosition>> get history => _history;

  /// Notifies when [history] changes.
  Listenable get historyChanges => _historyChanges;

  /// The last move, which [undoMove] can take back, and whether the store
  /// holds it, or null when there is none. A page turn keeps the offer.
  /// The next move, [undoMove], [dismissUndo], and the open of another
  /// book end it.
  UndoOffer<TextPosition>? get undoOffer => switch (_undo) {
    null => null,
    final action => (
      action: action,
      saved: _pendingWrites[_account]?.history.containsKey(action.id) != true,
    ),
  };

  /// Notifies when [undoOffer] changes.
  Listenable get undoChanges => _undoChanges;

  /// Notifies when [searching], [hits] or [searchError] changes.
  Listenable get searchChanges => _searchChanges;

  /// Notifies when [fontSize] or [sizesMainText] changes.
  Listenable get fontSizeChanges => _fontSizeChanges;

  /// Notifies when [saveFailed] changes.
  Listenable get saveStatusChanges => _saveStatusChanges;

  /// Whether the account has reading records that the store did not accept.
  /// The session keeps them and retries on each later write or [flush].
  bool get saveFailed => _failedAccounts.contains(_account);
  late final _Signal _placeChanges;
  late final _Signal _documentChanges;
  late final _Signal _bookmarkChanges;
  late final _Signal _historyChanges;
  late final _Signal _undoChanges;
  late final _Signal _searchChanges;
  late final _Signal _fontSizeChanges;
  late final _Signal _saveStatusChanges;
  late final _Signal _bookMapChanges;
  late final _Signal _timeLeftChanges;
  late final _Signal _keptPageChanges;
  late final List<_Signal> _signals;

  BookMap? _bookMap;

  /// Whether the open book is being measured for [bookMap].
  bool _mapping = false;

  /// The scrub deck's pages, which the shown viewport draws. Closing the
  /// book ends a scrub.
  late final previews = PagePreviews(
    draw: (place, width, abandon) {
      final navigator = _navigator;
      return navigator == null
          ? Future.error(StateError('No book is shown.'))
          : navigator.preview(place, width, abandon);
    },
    locate: (place) => _bookMap?.fractionAt(place) ?? 0,
  );

  /// Where places sit along the whole open book, for the scrub bar. It is
  /// null while no book is open and until the viewport lists the book's
  /// contents. In an EPUB or MOBI book it changes as the pager lays out
  /// sections, and after a change of the page settings.
  BookMap? get bookMap => _bookMap;

  /// Notifies when [bookMap] changes.
  Listenable get bookMapChanges => _bookMapChanges;

  /// The reading time left from the visible place to the end of its chapter
  /// and to the end of the book, at the person's [speed], each rounded as
  /// [roundEstimate] rounds it. Null while the speed is not known, and in a
  /// PDF. The place, the book map and the speed decide it.
  TimeLeft? get timeLeft {
    final perMinute = speed?.charactersPerMinute.value;
    final (place, map) = (_visibleAddress, _bookMap);
    if (perMinute == null || place == null || map == null) return null;
    final left = map.charactersLeft(place);
    if (left == null) return null;
    Duration time(double characters) => roundEstimate(
      Duration(milliseconds: (characters / perMinute * 60000).round()),
    );
    return (chapter: time(left.chapter), book: time(left.book));
  }

  /// Notifies when [timeLeft] changes. A page turn that leaves the rounded
  /// times as they were notifies nothing.
  Listenable get timeLeftChanges => _timeLeftChanges;

  /// The place of [bookmark] in the open book, or null when the bookmark
  /// belongs to other content.
  ReaderAddress? addressOf(Bookmark<TextPosition> bookmark) =>
      _compatible(bookmark.position);

  bool get ready => document != null && _navigator != null;
  bool get canBookmark => _recordsReady && position != null;
  List<Bookmark<TextPosition>> get bookmarks => List.unmodifiable(
    _bookmarks.where((mark) => mark.position.editionId == edition?.id),
  );

  Future<void> bind(JellyfinSession? account, List<Book> books) async {
    if (_disposed) return;
    _books = List.unmodifiable(books);
    final changed =
        _account != account?.scope.key || _credential != account?.token;
    if (!changed) {
      if (edition != null && !_current(edition!)) {
        _clear();
        _message = 'This edition is no longer available in this account. Return to the library and choose a current edition. Your saved places were kept.';
        _emit();
      }
      await _binding;
      if (!_recordsReady) await _readAgain();
      await _retryPending();
      return;
    }
    _account = account?.scope.key;
    _credential = account?.token;
    _clear();
    _resumes.clear();
    _bookmarks = const [];
    _history = const [];
    _recordsReady = false;
    _fontSize = _defaultFontSize;
    _sizesMainText = false;
    _legacyTrimMargins = true;
    _pdfBooks = const {};
    final generation = ++_accountGeneration;
    final key = _account;
    final previous = _binding;
    _binding = () async {
      await previous;
      await _retryPending();
      await _readRecords(generation, key);
    }();
    _emit();
    await _binding;
  }

  /// Reads the saved records of [key], the account of [generation], into
  /// this session, and makes the records ready. The changes that waited in
  /// [_unreadChanges] apply on top of the read records and are then saved.
  /// A read that fails leaves the records unread, with the changes still
  /// waiting, and shows [_recordsUnread]. [_readAgain] tries again.
  Future<void> _readRecords(int generation, String? key) async {
    if (!_liveAccount(generation) || key == null) return;
    var saveWaiting = false;
    try {
      var pending = _pendingWrites[key];
      final stored = await store.read(key);
      if (!_liveAccount(generation)) return;
      // No await from here to the end of the try block: a change made in
      // between would wait in [_unreadChanges] with nothing to save it.
      final waiting = _unreadChanges[key];
      if (waiting != null) {
        // The waiting changes name records only. Their settings came from
        // unread records, so the pending or the read settings stand.
        final changes = ReadingChanges(
          pending?.settings ??
              (stored == null
                  ? _settings()
                  : {
                      for (final MapEntry(:key, :value) in stored.entries)
                        if (!const {
                          'resumes',
                          'bookmarks',
                          'history',
                        }.contains(key))
                          key: value,
                    }),
          resumes: waiting.resumes,
          bookmarks: waiting.bookmarks,
          history: waiting.history,
        );
        pending = pending?.followedBy(changes) ?? changes;
      }
      final saved = pending == null ? stored : pending.applyTo(stored);
      if (saved != null) {
        if (saved['version'] != 1 ||
            saved['resumes'] is! List ||
            saved['bookmarks'] is! List ||
            (saved['resumes'] as List).any(
              (value) => value is! Map<String, dynamic>,
            ) ||
            (saved['bookmarks'] as List).any(
              (value) => value is! Map<String, dynamic>,
            )) {
          throw const FormatException('Invalid reading record.');
        }
        final resumes = (saved['resumes'] as List)
            .map((value) => decodeTextPosition(value as Map<String, dynamic>))
            .toList();
        final bookmarks = (saved['bookmarks'] as List)
            .map(
              (value) => Bookmark.fromJson(
                value as Map<String, dynamic>,
                decodeTextPosition,
              ),
            )
            .toList();
        if (bookmarks.map((mark) => mark.id).toSet().length !=
            bookmarks.length) {
          throw const FormatException('Duplicate reading bookmarks.');
        }
        final pdfBooks = _readPdfBooks(saved);
        _resumes
          ..clear()
          ..addAll(resumes);
        _bookmarks = bookmarks;
        _history = _moves(saved);
        final size = saved['fontSize'];
        if (size is num && size.isFinite) {
          _fontSize = size.toDouble().clamp(14, 40);
        }
        // A text size other than the default, saved before the choice
        // was saved, came from the size buttons.
        _sizesMainText =
            saved['sizesMainText'] == true || _fontSize != _defaultFontSize;
        _legacyTrimMargins = saved['trimMargins'] != false;
        _pdfBooks = pdfBooks;
      }
      if (waiting != null) {
        _unreadChanges.remove(key);
        _pendingWrites[key] = pending!;
        saveWaiting = true;
      }
      if (pending == null) store.acceptSnapshot(key, saved);
      _recordsReady = true;
      if (_message == _recordsUnread) _message = null;
    } on Exception {
      if (_liveAccount(generation)) _message = _recordsUnread;
    }
    _emit();
    if (saveWaiting) await _retryPending();
  }

  /// Reads the records of the bound account again when they are unread
  /// after a failed read. It runs after the reads that already wait.
  Future<void> _readAgain() {
    final generation = _accountGeneration;
    final key = _account;
    return _binding = _binding.then((_) async {
      if (!_recordsReady) await _readRecords(generation, key);
    });
  }

  bool _current(Edition selected) => _books.any(
    (work) => work.editions.any(
      (value) =>
          value.id == selected.id &&
          value.kind == EditionKind.text &&
          value.files.length == selected.files.length &&
          List.generate(
            value.files.length,
            (index) =>
                value.files[index].key == selected.files[index].key &&
                value.files[index].revision == selected.files[index].revision,
          ).every((same) => same),
    ),
  );

  bool _live(int generation) => !_disposed && generation == token;
  bool _liveAccount(int generation) =>
      !_disposed && generation == _accountGeneration;
  void _clear() {
    _keepShown();
    _dropKeptPage();
    _readingKeptPage = false;
    ++_token;
    ++_search;
    previews.close();
    _navigator = null;
    _pager?.bookPages.removeListener(_repage);
    _pager?.dispose();
    _pager = null;
    final previous = _document;
    if (previous is PdfBook) previous.textSupply?.cancel();
    _document = null;
    if (previous != null) {
      _closing = _closing.then((_) => previous.dispose()).onError<Exception>((
        error,
        stack,
      ) {
        _releaseFailed = true;
      });
    }
    _edition = null;
    _book = null;
    _position = null;
    _visibleAddress = null;
    _initialAddress = null;
    _loading = false;
    _searching = false;
    _hits = const [];
    _contents = const [];
    _bookMap = null;
    _mapping = false;
    _searchError = null;
    _message = null;
    _undo = null;
    _pending = null;
    _landed = null;
    _jumps = Future.value();
  }

  /// Opens [selected], an ebook edition of [book], at its saved place, or
  /// at [at] when that place fits the edition.
  Future<void> open(Book book, Edition selected, {TextPosition? at}) =>
      _open(book, selected, at: at);

  /// Opens [selected] at its saved place, or at [at], a place in it, as a
  /// move of [kind]. The first place that the book shows ends the move:
  ///
  /// - With [from], the shown place in another edition of the same book,
  ///   the move goes from [from], and the visit goes on.
  /// - Otherwise the open starts a visit. When the book opens somewhere
  ///   other than this phone's own last place in [selected], the move goes
  ///   from that place: to [at], or, without [at], to a place that another
  ///   device saved. Else the visit starts with an Opened entry.
  ///
  /// If [at] cannot be found in the book, the book opens at its saved
  /// place, and only a new visit records its start.
  Future<void> _open(
    Book book,
    Edition selected, {
    TextPosition? at,
    HistoryAction kind = HistoryAction.open,
    TextPosition? from,
  }) async {
    if (_disposed || _account == null || !_current(selected)) return;
    if (from == null) _closeVisit();
    _clear();
    _book = book;
    _edition = selected;
    _loading = true;
    final generation = token;
    _emit();
    await _binding;
    if (!_live(generation) || !_current(selected)) return;
    // The book opens at its saved place, unless [at] names another, so the
    // page kept there can show while the book loads. A PDF keeps no page.
    final keptAt =
        at != null ||
            selected.files.length != 1 ||
            selected.files.single.container.toLowerCase() == 'pdf'
        ? null
        : _resumes.where((value) => value.editionId == selected.id).lastOrNull;
    if (keptPages != null && keptAt != null) {
      _readingKeptPage = true;
      _emit();
    }
    // The query runs while the book loads. A failed query knows nothing.
    final origin = at != null || selected.files.length != 1
        ? null
        : store
              .origin(_account!, selected)
              .then<PlaceOrigin?>(
                (value) => value,
                onError: (Object _) => null,
              );
    try {
      await _closing;
      if (_releaseFailed) {
        throw const FormatException(
          'A previous document could not be released. Restart Bookfin before opening another ebook.',
        );
      }
      if (selected.kind != EditionKind.text || selected.files.length != 1) {
        throw const FormatException('Choose a single-file ebook edition.');
      }
      // The loads hold the download for the files that they write beside
      // it after they gave their book ([VerifiedFile.hold]).
      final admitted = await downloads.readLocalFile<ReaderDocument>(
        selected.files.single,
        (file) async {
          if (file.uri.scheme != 'file') {
            throw const FormatException(
              'The reader requires a verified local download.',
            );
          }
          if (_readingKeptPage && keptAt != null) {
            unawaited(_readKeptPage(generation, file, keptAt));
          }
          return loadDocument == null
              ? EpubDocument(await load(file))
              : await loadDocument!(file, selected.files.single);
        },
      );
      if (admitted == null) {
        throw const FormatException(
          'Download this ebook before reading. Only verified local files can open.',
        );
      }
      final known = await origin;
      if (!_live(generation) || !_current(selected)) {
        await admitted.dispose();
        return;
      }
      _document = admitted;
      if (admitted is PdfBook) {
        admitted.textSupply?.bind(
          (read) => _lend(
            selected,
            const PdfText(
              source: '',
              text: '',
              sourceOffsets: [],
              status: PdfTextStatus.failed,
              reason: 'The download of this book is no longer available.',
            ),
            read,
          ),
        );
      }
      final candidates = _resumes
          .where((value) => value.editionId == selected.id)
          .toList();
      final saved =
          [
            ?at,
            ...candidates.reversed,
          ].where((value) => _compatible(value) != null).firstOrNull ??
          candidates.lastOrNull;
      _initialAddress = at == null ? null : _compatible(at);
      final opensAt = _initialAddress != null;
      if (at != null && !opensAt) _message = _unknownPlace;
      if (_initialAddress == null && saved != null) {
        _initialAddress = _compatible(saved);
        if (initialAddress == null) {
          _message = 'The saved place belongs to different source or processed content. The old place and bookmarks were kept. Reading starts at the beginning.';
        }
      }
      if (admitted is PdfBook) _survey(admitted, selected);
      // This phone's own last place in the edition, which the open leaves:
      // for an open at [at], the saved place, and otherwise the place that
      // this phone saved before another device saved the opened place.
      final own = opensAt
          ? switch (candidates.reversed
                .where((value) => _compatible(value) != null)
                .firstOrNull) {
              final own? when !samePlace(own, at!) => own,
              _ => null,
            }
          : saved == null || initialAddress == null
          ? null
          : switch (openedFrom(known, saved, _history)) {
              final own? when _compatible(own) != null => own,
              _ => null,
            };
      _pending = switch ((from, own)) {
        (final from?, _) when opensAt => _Move(kind, from, token: generation),
        // A jump to another edition that cannot find its place opens the
        // saved place, and the visit goes on without a move.
        (_?, _) => null,
        (null, final own?) => _Move(
          opensAt ? kind : HistoryAction.open,
          own,
          device: opensAt ? null : known!.device,
          token: generation,
        ),
        (null, null) => _Move(HistoryAction.open, null, token: generation),
      };
      if (!_recordsReady) {
        _message = _recordsUnread;
      } else if (store.setAside(_account!)) {
        _message ??= 'Saved reading records were damaged. Bookfin kept a copy and restored the places that it could read. The next sync restores the rest.';
      }
      if (admitted is EpubDocument) {
        final contents = await _contentsOf(admitted.publication);
        if (!_live(generation)) return;
        final pager = _pager = EpubPager(
          admitted,
          initial: _initialAddress,
          expected: pageSettings?.value,
          onPlace: (address) => acceptAddress(generation, address),
          onWarning: (message) => warn(generation, message),
          onShow: (read) {
            if (!_live(generation)) return;
            if (_dropKeptPage()) _emit();
            speed?.pageShown(read: read);
            if (_pager?.shown.value?.page.settings case final settings?) {
              pageSettings?.keep(settings);
            }
          },
        );
        pager.bookPages.addListener(_repage);
        attachDocument(generation, pager, contents);
      }
    } on FormatException catch (error) {
      if (_live(generation)) {
        _pending = null;
        _message = error.message;
      }
    } catch (_) {
      if (_live(generation)) {
        _pending = null;
        _message = 'The downloaded ebook could not be opened. Check the download, then retry.';
      }
    } finally {
      if (_live(generation)) {
        _loading = false;
        // A book that did not open, or a PDF, shows no kept page.
        if (_pager == null) {
          _readingKeptPage = false;
          _dropKeptPage();
        }
        _emit();
      }
    }
  }

  /// Reads the page kept at the saved place [at] of [original], the download
  /// of the book that the open [generation] opens, for [keptPage]. A page
  /// that comes after the open ended, or after its pager showed a page, is
  /// let go.
  Future<void> _readKeptPage(
    int generation,
    VerifiedFile original,
    TextPosition at,
  ) async {
    KeptPage? kept;
    try {
      kept = await keptPages!.read(original, at);
    } on Exception {
      // A kept page is derived: without one, the reader waits for the book.
    }
    if (!_live(generation) ||
        !_readingKeptPage ||
        _pager?.shown.value != null) {
      kept?.dispose();
      return;
    }
    _readingKeptPage = false;
    _keptPage = kept;
    _emit();
  }

  /// Lets go of [keptPage]. Gives whether there was one.
  bool _dropKeptPage() {
    final kept = _keptPage;
    _keptPage = null;
    kept?.dispose();
    return kept != null;
  }

  /// Keeps the page that the open EPUB or MOBI book shows as the kept page
  /// of its saved place ([keptPages]), when an open at that place shows
  /// that page ([EpubPager.opensAtShown]).
  ///
  /// It encodes the page on the UI isolate, where its paragraphs live, and
  /// writes it under a hold of the download. A kept page is derived data,
  /// so no failure of it stops the close or the save that calls it.
  void _keepShown() {
    try {
      final (pages, selected, place, pager) = (
        keptPages,
        _edition,
        _position,
        _pager,
      );
      final page = pager?.shown.value?.page;
      if (pages == null ||
          selected == null ||
          place == null ||
          page == null ||
          !pager!.opensAtShown) {
        return;
      }
      final body = KeptPage.encode(page);
      if (body == null) return;
      _keeping = _keeping
          .then((_) async {
            final started = await _lend<({Future<void> held})?>(
              selected,
              null,
              (original, _) async => (held: pages.write(original, place, body)),
            );
            await started?.held;
          })
          .onError<Object>((_, _) {});
    } on Object {
      // The next close keeps a page again.
    }
  }

  ReaderAddress? _compatible(TextPosition saved) {
    final admitted = document;
    if (edition == null || admitted == null || !saved.fits(edition!)) {
      return null;
    }
    try {
      final anchor = jsonDecode(saved.anchor) as Map<String, dynamic>;
      return admitted.restore(anchor);
    } catch (_) {
      return null;
    }
  }

  void attachDocument(
    int eventToken,
    DocumentNavigator navigator,
    List<ContentsEntry> entries,
  ) {
    if (!_live(eventToken) || document == null) return;
    _navigator = navigator;
    _contents = List.unmodifiable(entries);
    if (_bookMap == null && !_mapping) {
      unawaited(_mapBook(eventToken, document!, _contents));
    }
    _emit();
  }

  /// Measures the open [document] for [bookMap], once for each open book. A
  /// PDF lists its contents again on each page, and its map does not change.
  Future<void> _mapBook(
    int eventToken,
    ReaderDocument document,
    List<ContentsEntry> contents,
  ) async {
    _mapping = true;
    final map = await BookMap.of(document, contents);
    if (!_live(eventToken)) return;
    _mapping = false;
    _bookMap = switch ((map, _pager)) {
      (final map?, final pager?) => map.paged(pager.bookPages.value),
      _ => map,
    };
    _emit();
  }

  /// Spaces the book map by the pages that the pager laid out, once a
  /// section is laid out or the page settings change.
  void _repage() {
    final (map, pager) = (_bookMap, _pager);
    if (map == null || pager == null) return;
    _bookMap = map.paged(pager.bookPages.value);
    _emit();
  }

  void failed(int eventToken, String explanation) {
    if (!_live(eventToken)) return;
    _navigator = null;
    _message = explanation;
    _emit();
  }

  /// Shows [explanation], a warning of the pager. A warning that comes
  /// while a page shows and the book reported no place yet means that the
  /// pager could not find the place that the book opened at, and shows the
  /// book's start instead. The open, or the jump that opened the book,
  /// then ends without a move.
  void warn(int eventToken, String explanation) {
    if (!_live(eventToken)) return;
    if (_visibleAddress == null && _pager?.shown.value != null) {
      _pending = null;
    }
    _message = explanation;
    _emit();
  }

  /// Closes the shown book when the reader leaves it, as Back does, and
  /// ends its reading visit.
  void closeView(int eventToken) {
    if (!_live(eventToken)) return;
    _closeVisit();
    _clear();
  }

  void acceptVisible(int eventToken, VisibleLocation location) =>
      acceptAddress(eventToken, EpubAddress(location));

  /// Takes [address] as the place that the navigator now shows. It becomes
  /// the visible place and is saved. The first place after a jump ends the
  /// pending move (see [_endMove]).
  void acceptAddress(int eventToken, ReaderAddress address) {
    if (!_place(eventToken, address)) return;
    final move = _landed = _endMove(address);
    unawaited(_save(resumes: [position!], history: {?move?.id: move}));
    _emit();
  }

  /// Names the visible place more exactly. [address] is a place on the page
  /// that already shows, as the text of that page names it once the text
  /// arrives. It becomes the visible place and is saved, like a page turn.
  ///
  /// A refinement records no move. The move that ended when the page
  /// showed, if any, now ends at [address], so History shows the words of
  /// the place.
  ///
  /// A refinement never changes the page. An [address] in another resource
  /// than the visible place changes nothing, so a late text of an earlier
  /// page cannot move the place back. An [address] that names the place as
  /// it is already named saves nothing.
  void refineAddress(int eventToken, ReaderAddress address) {
    final shown = _visibleAddress, earlier = _position;
    if (shown == null ||
        earlier == null ||
        shown.resource != address.resource ||
        jsonEncode(shown.toJson()) == jsonEncode(address.toJson())) {
      return;
    }
    if (!_place(eventToken, address)) return;
    final move = _landed = _nameEnds(_landed, earlier);
    unawaited(_save(resumes: [position!], history: {?move?.id: move}));
    _emit();
  }

  /// Makes [address] the visible place and the saved position, when the
  /// book of [eventToken] is open and holds [address]. Gives whether it did.
  bool _place(int eventToken, ReaderAddress address) {
    final admitted = document;
    if (!_live(eventToken) ||
        admitted == null ||
        edition == null ||
        !admitted.accepts(address)) {
      return false;
    }
    try {
      admitted.decodeAddress(address.toJson());
    } catch (_) {
      return false;
    }
    _visibleAddress = address;
    // The survey analyzes the shown page and the next one first, so the next
    // page's crop is normally ready before a turn.
    if ((admitted, address) case (
      final PdfBook book,
      PdfAddress(:final sourcePage),
    )) {
      book.survey.follow(sourcePage);
    }
    _position = TextPosition(
      editionId: edition!.id,
      sourceKey: edition!.files.single.key,
      revision: edition!.files.single.revision,
      anchor: jsonEncode(admitted.save(address)),
      sourcePage: address is PdfAddress ? address.sourcePage : null,
    );
    _resumes.removeWhere(
      (saved) =>
          saved.editionId == position!.editionId &&
          saved.sourceKey == position!.sourceKey &&
          saved.revision == position!.revision &&
          _compatible(saved) != null,
    );
    _resumes.add(position!);
    return true;
  }

  /// Gives [move] the visible place at each end where it names [earlier],
  /// the same place before its text named it. The start of a visit names it
  /// at both ends. Gives the changed move, which replaces [move] in
  /// [history] and in the Undo offer. Null when [move] is null, or when
  /// [history] holds it no more.
  HistoryEvent<TextPosition>? _nameEnds(
    HistoryEvent<TextPosition>? move,
    TextPosition earlier,
  ) {
    final index = move == null
        ? -1
        : _history.indexWhere((event) => event.id == move.id);
    if (index < 0) return null;
    final old = _history[index];
    TextPosition named(TextPosition end) =>
        samePlace(end, earlier) ? position! : end;
    final renamed = HistoryEvent(
      id: old.id,
      at: old.at,
      kind: old.kind,
      before: named(old.before),
      after: named(old.after),
      bookTitle: old.bookTitle,
      editionLabel: old.editionLabel,
      device: old.device,
      counterpartOf: old.counterpartOf,
      matchedBy: old.matchedBy,
    );
    _history = List.of(_history)..[index] = renamed;
    if (_undo?.id == old.id) _undo = renamed;
    return renamed;
  }

  /// Ends the pending move at [after], the place that the navigator now
  /// shows, and records it, unless it ends on the page where it began.
  /// Gives the recorded move, which becomes the Undo offer. An undo move
  /// ends the offer.
  HistoryEvent<TextPosition>? _endMove(ReaderAddress after) {
    final move = _pending;
    _pending = null;
    if (move == null ||
        move.token != token ||
        (move.before?.editionId == edition!.id &&
            _onPage(after, move.shown, move.end))) {
      return null;
    }
    final event = _record(
      move.kind,
      move.before ?? position!,
      position!,
      device: move.device,
      counterpart: move.counterpart,
    );
    if (move.before != null) {
      _undo = move.kind == HistoryAction.undo ? null : event;
    }
    return event;
  }

  /// Adds an entry of [kind] from [before] to [after] in the open book to
  /// [history], and gives it.
  HistoryEvent<TextPosition> _record(
    HistoryAction kind,
    TextPosition before,
    TextPosition after, {
    String? device,
    _Counterpart? counterpart,
  }) {
    final event = HistoryEvent(
      id: recordId(),
      at: DateTime.now().toUtc(),
      kind: kind,
      before: before,
      after: after,
      bookTitle: _book!.title,
      editionLabel: edition!.label,
      device: device,
      counterpartOf: counterpart?.place,
      matchedBy: counterpart?.matchedBy,
    );
    _history = [event, ..._history];
    return event;
  }

  /// Ends the reading visit of the shown book: records a Closed entry at
  /// the shown place. Without a shown place, the visit records nothing.
  void _closeVisit() {
    final place = position;
    if (place == null || !_recordsReady) return;
    final event = _record(HistoryAction.close, place, place);
    unawaited(_save(history: {event.id: event}));
  }

  /// Whether [place] lies on the page that showed [shown], from its start
  /// to [end], the page's last place where the pager knew it. Without a
  /// book map that can place both, only [shown] itself is on the page.
  bool _onPage(ReaderAddress place, ReaderAddress? shown, BookPlace? end) {
    if (shown == null) return false;
    final map = _bookMap;
    final at = map?.fractionOf(place);
    final start = map?.fractionOf(shown);
    if (map == null || at == null || start == null) {
      return jsonEncode(place.toJson()) == jsonEncode(shown.toJson());
    }
    // Places measured on two paths can differ in the last bits.
    const near = 1e-9;
    final last = end == null ? start : map.fractionAt(end);
    return at >= start - near && at <= last + near;
  }

  Future<void> addBookmark({String? title, String? note}) async {
    final current = position;
    if (current == null || !_recordsReady) return;
    final added = Bookmark(
      id: recordId(),
      position: current,
      createdAt: DateTime.now(),
      bookTitle: _book?.title,
      editionLabel: _edition?.label,
      title: title,
      note: note,
    );
    _bookmarks = [..._bookmarks, added];
    await _save(bookmarks: {added.id: added});
    _emit();
  }

  Future<void> editBookmark(String id, {String? title, String? note}) async {
    final index = _bookmarks.indexWhere((value) => value.id == id);
    if (index < 0) return;
    final old = _bookmarks[index];
    // An edit in the open edition names the book and the edition as they
    // are now, so a bookmark saved before book names gets them. A bookmark
    // of another edition, renamed from the History timeline, keeps its own.
    final here = old.position.editionId == _edition?.id;
    final edited = Bookmark(
      id: old.id,
      position: old.position,
      createdAt: old.createdAt,
      bookTitle: (here ? _book?.title : null) ?? old.bookTitle,
      editionLabel: (here ? _edition?.label : null) ?? old.editionLabel,
      title: title,
      note: note,
    );
    _bookmarks = List.of(_bookmarks)..[index] = edited;
    await _save(bookmarks: {id: edited});
    _emit();
  }

  Future<void> deleteBookmark(String id) async {
    _bookmarks = _bookmarks.where((value) => value.id != id).toList();
    await _save(bookmarks: {id: null});
    _emit();
  }

  /// Shows the bookmark [id], as a bookmark restore move. A bookmark in
  /// another ebook edition opens that edition there (see [_jumpTo]).
  Future<void> restoreBookmark(String id) async {
    final saved = _bookmarks.where((value) => value.id == id).firstOrNull;
    if (saved == null) return;
    await _jumpTo(
      HistoryAction.bookmarkRestore,
      saved.position,
      unknown: 'This bookmark belongs to different source or processed content and cannot be applied.',
    );
  }

  /// Shows where the move [id] of [history] began, or with [previous]
  /// false, where it ended, as a history restore move. A place in another
  /// ebook edition opens that edition there (see [_jumpTo]).
  Future<void> restoreHistory(String id, {bool previous = true}) async {
    final event = _history.where((value) => value.id == id).firstOrNull;
    if (event == null) {
      throw ArgumentError('Choose history from the current account.');
    }
    await _jumpTo(
      HistoryAction.historyRestore,
      previous ? event.before : event.after,
    );
  }

  /// Shows [landing], where a place of an audio edition lands in the open
  /// ebook edition, as a move of [kind] in the reading track from the shown
  /// place, with Undo: a mapped move. The move names the audio place that it
  /// went to and how Bookfin found the landing. No listening record changes.
  /// Completes with whether the landing showed: a landing in another edition,
  /// or in another revision of the open file, moves nothing.
  Future<bool> goToLanding(TextLanding landing, HistoryAction kind) async {
    if (!_canShow(landing)) return false;
    final (:part, :progress) = landing.place;
    return _jump(
      kind,
      (navigator) => navigator.seek(part, progress),
      counterpart: (place: landing.from, matchedBy: landing.matchedBy),
    );
  }

  /// Takes back the move of [undoOffer]: shows the place where it began, as
  /// an undo move, and ends the offer. If that place cannot be shown, the
  /// offer stays.
  Future<void> undoMove() async {
    final offer = _undo;
    if (offer == null) return;
    if (await _jumpTo(HistoryAction.undo, offer.before) &&
        identical(_undo, offer)) {
      _undo = null;
      _emit();
    }
  }

  /// Ends [undoOffer] and keeps its move.
  void dismissUndo() {
    _undo = null;
    _emit();
  }

  /// The bookmark of the open edition whose place lies on the shown page,
  /// from its start to its end, or null. The newest such bookmark wins. It
  /// follows [bookmarkChanges], [placeChanges] and [bookMapChanges].
  Bookmark<TextPosition>? get bookmarkHere {
    final shown = _visibleAddress;
    if (shown == null) return null;
    for (final mark in _bookmarks.reversed) {
      if (mark.position.editionId != edition?.id) continue;
      final place = _compatible(mark.position);
      if (place != null && _onPage(place, shown, _pager?.shownEnd)) {
        return mark;
      }
    }
    return null;
  }

  /// Shows [target] as a move of [kind]. A place in the open edition shows
  /// there. A place in another current ebook edition opens that edition at
  /// the place. From another edition of the open book, the move goes from
  /// the shown place. From anywhere else, the open starts a visit, and the
  /// move goes from the edition's own saved place (see [_open]). If the
  /// place cannot be found, [message] says [unknown]. Completes with
  /// whether the place showed.
  Future<bool> _jumpTo(
    HistoryAction kind,
    TextPosition target, {
    String unknown = _unknownPlace,
  }) async {
    if (target.editionId == _edition?.id) {
      final address = _compatible(target);
      if (address != null) {
        return _jump(kind, (navigator) => navigator.display(address));
      }
    } else if (_books
            .expand(
              (book) => [for (final edition in book.editions) (book, edition)],
            )
            .where((pair) => target.fits(pair.$2) && _current(pair.$2))
            .firstOrNull
        case (final book, final other)?) {
      await _open(
        book,
        other,
        at: target,
        kind: kind,
        from: book.id == _book?.id ? position : null,
      );
      return document != null && identical(edition, other);
    }
    _message = unknown;
    _emit();
    return false;
  }

  /// Asks the navigator for a jump with [go], as a move of [kind] from the
  /// shown place. Jumps in one book run one after another, so each one
  /// begins where the one before it ended. Completes with whether the
  /// navigator did not fail. A jump that waits when another book opens
  /// does not run.
  Future<bool> _jump(
    HistoryAction kind,
    Future<void> Function(DocumentNavigator navigator) go, {
    _Counterpart? counterpart,
  }) {
    final generation = token;
    final jump = _jumps.then((_) async {
      final navigator = _navigator;
      if (navigator == null || !_live(generation)) return false;
      final before = position;
      // A jump before the book shows a place has no place to begin from,
      // and leaves the start of the visit pending.
      final move = before == null
          ? null
          : _pending = _Move(
              kind,
              before,
              shown: _visibleAddress,
              end: _pager?.shownEnd,
              token: token,
              counterpart: counterpart,
            );
      try {
        return await _navigate(() => go(navigator));
      } finally {
        if (identical(_pending, move)) _pending = null;
      }
    });
    _jumps = jump.then((_) {}, onError: (Object _) {});
    return jump;
  }

  /// Deletes the reading move [id] from the account's history, here and,
  /// after sync, on the account's other devices.
  Future<void> deleteHistory(String id) async {
    _history = _history.where((value) => value.id != id).toList();
    await _save(history: {id: null});
    _emit();
  }

  /// [place] in words, for the History timeline and the bookmark editor
  /// (see [describeTextPlace]). A place in the open book reads by the
  /// current [bookMap], so its page number follows [bookMapChanges].
  PlaceWords describe(TextPosition place) =>
      describeTextPlace(place, address: _compatible(place), map: _bookMap);

  /// [landing] in words, as [describe] names a place in the open book: its
  /// page once the book's map knows its pages, else its share of the book,
  /// and its chapter. The share and, where the map names no chapter, as in
  /// a PDF, the chapter come from the text outline that placed the landing.
  /// So it follows [bookMapChanges]. Null exactly when [goToLanding] moves
  /// nothing: while the reader shows no book, and when [landing] is not in
  /// the open edition at the file revision that the reader shows.
  PlaceWords? describeLanding(TextLanding landing) {
    if (!_canShow(landing)) return null;
    final map = _bookMap;
    final target = map?.targetAt(map.fractionAt(landing.place));
    return switch (target?.page) {
      final page? => describeAlong(
        target!.fraction,
        page: page,
        chapter: target.chapter ?? landing.chapter,
      ),
      null => describeAlong(
        landing.share,
        chapter: target?.chapter ?? landing.chapter,
      ),
    };
  }

  /// Whether the reader can show [landing] now: it shows a book, and
  /// [landing] is in the open edition, at the file revision that the reader
  /// shows.
  bool _canShow(TextLanding landing) {
    final (edition, into) = (_edition, landing.into);
    return ready &&
        edition != null &&
        edition.id == into.editionId &&
        edition.files.single.key == into.sourceKey &&
        edition.files.single.revision == into.revision;
  }

  /// The reading moves and bookmarks of [book]'s editions, or of every
  /// book, newest first. It follows [historyChanges] and [bookmarkChanges].
  /// The list stays the same object until they change or another book is
  /// asked for.
  List<TimelineEntry> timeline(Book? book) {
    final key = (_history, _bookmarks, book);
    if (_timeline case (final kept, final entries) when kept == key) {
      return entries;
    }
    bool belongs(TextPosition place) =>
        book == null ||
        book.editions.any((edition) => edition.id == place.editionId);
    final entries = List<TimelineEntry>.unmodifiable(
      <TimelineEntry>[
        for (final event in _history)
          if (belongs(event.after)) ActionEntry(event),
        for (final bookmark in _bookmarks)
          if (belongs(bookmark.position)) BookmarkEntry(bookmark),
      ]..sort((first, second) => second.at.compareTo(first.at)),
    );
    _timeline = (key, entries);
    return entries;
  }

  /// The last [timeline], and the records and book that it lists. Records
  /// compare by identity, because each change replaces its list.
  (
    (List<HistoryEvent<TextPosition>>, List<Bookmark<TextPosition>>, Book?),
    List<TimelineEntry>,
  )?
  _timeline;

  /// Runs [action] on the navigator. If it fails, [message] says so.
  /// Completes with whether it did not fail.
  Future<bool> _navigate(Future<void> Function() action) async {
    final generation = token;
    try {
      await action();
      return true;
    } catch (_) {
      if (_live(generation)) {
        _message = 'The reading destination could not be opened. Your saved place was kept.';
        _emit();
      }
      return false;
    }
  }

  Future<void> move(bool forward) async {
    final navigator = _navigator;
    if (navigator != null) await _navigate(() => navigator.move(forward));
  }

  /// Whether the open book has chapters on its map. The chapter arrows then
  /// step between chapters. A book without them, such as a PDF, whose
  /// contents list pages, turns pages instead.
  bool get hasChapters => _bookMap?.chapters.isNotEmpty ?? false;

  /// Shows the start of the next chapter with [forward]. Back, it shows the
  /// start of the chapter that holds the visible place, or of the chapter
  /// before when the visible place is that start (see
  /// [BookMap.chapterStep]). With no chapter that way it does nothing. In a
  /// book without chapters it turns one page, like [move].
  Future<void> moveChapter(bool forward) async {
    if (!hasChapters) return move(forward);
    await _jump(HistoryAction.chapter, (navigator) async {
      final (map, place) = (_bookMap, _visibleAddress);
      final start = map == null || place == null
          ? null
          : map.chapterStep(place, forward: forward, end: _pager?.shownEnd);
      if (start == null) return;
      final target = map!.targetAt(start);
      await navigator.seek(target.part, target.progress);
    });
  }

  /// Shows [target], a place that the scrub bar chose in the open book. The
  /// viewport then reports the page that it shows, which becomes the visible
  /// place and is saved like a page turn. If the viewport cannot show it,
  /// the place stays and [message] says so.
  Future<void> goTo(BookTarget target) => _jump(
    HistoryAction.seek,
    (navigator) => navigator.seek(target.part, target.progress),
  );

  /// Shows the destination of the contents entry [href].
  Future<void> goToContents(String href) =>
      _jump(HistoryAction.chapter, (navigator) => navigator.contents(href));

  /// Shows [href], the destination of a link on the page or of Go to note,
  /// relative to the package document's directory.
  Future<void> followLink(String href) =>
      _jump(HistoryAction.link, (navigator) => navigator.contents(href));

  /// Validated settings snapshots. A choice replaces the table and its entry;
  /// a position save reuses it, and pending saves retain their original table.
  Map<String, Map<String, dynamic>> _pdfBooks = const {};
  bool _legacyTrimMargins = true;
  late final _Signal _pdfViewChanges;

  /// The open book's saved PDF view in this account: original pages,
  /// page words or reading text. An untouched book starts on original pages.
  PdfPageView get pdfView => switch (_pdfBooks[book?.id]?['view']) {
    final String view => PdfPageView.values.byName(view),
    _ => PdfPageView.original,
  };

  /// Whether original PDF pages and their deck cards show their known
  /// content crop instead of the full printed page. Saved per book in the
  /// account, with legacy account-wide trim as the fallback, otherwise on.
  /// The word view never uses it.
  bool get trimMargins =>
      _pdfBooks[book?.id]?['trimMargins'] as bool? ?? _legacyTrimMargins;
  late final _Signal _trimMarginsChanges;

  static Map<String, Map<String, dynamic>> _readPdfBooks(
    Map<String, dynamic> saved,
  ) {
    if (!saved.containsKey('pdfBooks')) return {};
    final books = saved['pdfBooks'];
    if (books is! Map<String, dynamic>) {
      throw const FormatException('Invalid PDF preferences.');
    }
    final preferences = <String, Map<String, dynamic>>{};
    for (final entry in books.entries) {
      final value = entry.value;
      if (entry.key.isEmpty || value is! Map<String, dynamic>) {
        throw const FormatException('Invalid book PDF preferences.');
      }
      final view = PdfPageView.values
          .where((view) => view.name == value['view'])
          .firstOrNull;
      final trim = value['trimMargins'];
      if (view == null || trim is! bool) {
        throw const FormatException('Invalid book PDF preferences.');
      }
      preferences[entry.key] = {'view': view.name, 'trimMargins': trim};
    }
    return preferences;
  }

  /// Notifies when [trimMargins] changes.
  Listenable get trimMarginsChanges => _trimMarginsChanges;

  /// Shows the chosen PDF margins at once and saves the choice. Old deck
  /// cards are freed so that the next scrub uses the chosen margins too.
  Future<void> setTrimMargins(bool on) async {
    final id = book?.id;
    if (id == null ||
        document is! PdfBook ||
        !_recordsReady ||
        trimMargins == on) {
      return;
    }
    _pdfBooks = {
      ..._pdfBooks,
      id: {'view': pdfView.name, 'trimMargins': on},
    };
    previews.close();
    _emit();
    await _save();
  }

  /// Notifies when [pdfView] changes.
  Listenable get pdfViewChanges => _pdfViewChanges;

  /// Shows [view] at once and saves it for this book in this account.
  Future<void> setPdfView(PdfPageView view) async {
    final id = book?.id;
    if (id == null ||
        document is! PdfBook ||
        !_recordsReady ||
        pdfView == view) {
      return;
    }
    _pdfBooks = {
      ..._pdfBooks,
      id: {'view': view.name, 'trimMargins': trimMargins},
    };
    _emit();
    await _save();
  }

  /// Sets the text size to [size], from 14 to 40 pixels, as the size of
  /// each book's main text from now on ([sizesMainText]).
  Future<void> setFontSize(double size) async {
    if (!size.isFinite) return;
    _fontSize = size.clamp(14, 40);
    _sizesMainText = true;
    await _save();
    _emit();
  }

  /// Makes the open book's main text one step (2 pixels) larger or
  /// smaller, from 14 to 40 pixels, with [setFontSize]. A step goes from
  /// the main text size that the open book shows, in the reader's pixels
  /// before the system text scale. That is [fontSize] once [sizesMainText]
  /// is on. Before that, a book that fixes its own type sizes shows its own
  /// main text size, so the first step goes from that size, and each step
  /// moves the text the way that it names. A step that has no size left
  /// that way does nothing. Each step waits for the one before it. When the
  /// shown size cannot be measured, the step goes from [fontSize].
  Future<void> stepFontSize({required bool larger}) {
    final step = _steps.then((_) async {
      final pager = _pager;
      var from = _fontSize;
      if (!_sizesMainText && pager != null) {
        try {
          from *= await pager.shownMainTextRatio() ?? 1;
        } catch (_) {
          // NOTE: Preparing the book's sections reports what the
          // measurement could not read.
        }
        if (_disposed) return;
      }
      final size = (from + (larger ? 2 : -2)).roundToDouble().clamp(14.0, 40.0);
      if (larger ? size > from : size < from) await setFontSize(size);
    });
    _steps = step.then((_) {}, onError: (Object _) {});
    return step;
  }

  /// The end of the last [stepFontSize].
  Future<void> _steps = Future.value();

  Future<void> search(String query) async {
    final navigator = _navigator;
    if (navigator == null) return;
    final generation = token;
    final request = ++_search;
    _hits = const [];
    _searchError = null;
    _searching = true;
    _emit();
    try {
      final report = await navigator.search(query, request);
      if (!_live(generation) || request != _search) return;
      _hits = List.unmodifiable(report.hits);
      _searchError = report.error;
    } catch (_) {
      if (_live(generation) && request == _search) _searchError = 'Search is incomplete. A chapter could not be searched. Retry or use Contents.';
    } finally {
      if (_live(generation) && request == _search) {
        _searching = false;
        _emit();
      }
    }
  }

  void cancelSearch() {
    final request = _search++;
    unawaited(_navigator?.cancelSearch(request).catchError((Object _) {}));
    _searching = false;
    _hits = const [];
    _searchError = null;
    _emit();
  }

  Future<void> openHit(ReaderHit hit) async {
    if (hits.contains(hit)) {
      await _jump(
        HistoryAction.search,
        (navigator) => navigator.display(hit.address),
      );
    }
  }

  /// Hands the store the [resumes], [bookmarks] and [history] that one
  /// action changed, with the current settings. A null bookmark or move is
  /// a deletion. The changes stay pending, merged with earlier pending
  /// changes, until the store saves them.
  Future<void> _save({
    List<TextPosition> resumes = const [],
    Map<String, Bookmark<TextPosition>?> bookmarks = const {},
    Map<String, HistoryEvent<TextPosition>?> history = const {},
  }) async {
    final key = _account;
    if (key == null || _disposed) return;
    ++_recordRevision;
    final changes = ReadingChanges(
      _settings(),
      resumes: resumes.map(encodeTextPosition).toList(),
      bookmarks: {
        for (final MapEntry(key: id, value: mark) in bookmarks.entries)
          id: mark?.toJson(),
      },
      history: {
        for (final MapEntry(key: id, value: move) in history.entries)
          id: move?.toJson(),
      },
    );
    if (!_recordsReady) {
      _unreadChanges[key] = _unreadChanges[key]?.followedBy(changes) ?? changes;
      await _readAgain();
      return;
    }
    _pendingWrites[key] = _pendingWrites[key]?.followedBy(changes) ?? changes;
    await _retryPending();
  }

  /// The version and the reading preferences as a save carries them.
  Map<String, dynamic> _settings() => {
    'version': 1,
    'fontSize': fontSize,
    if (sizesMainText) 'sizesMainText': true,
    if (!_legacyTrimMargins) 'trimMargins': false,
    if (_pdfBooks.isNotEmpty) 'pdfBooks': _pdfBooks,
  };

  Future<void> _retryPending() {
    _writes = _writes.then((_) async {
      for (final entry in _pendingWrites.entries.toList()) {
        try {
          await store.saveReading(entry.key, entry.value);
          if (identical(_pendingWrites[entry.key], entry.value)) {
            _pendingWrites.remove(entry.key);
            _failedAccounts.remove(entry.key);
          }
        } on Exception {
          _failedAccounts.add(entry.key);
        }
      }
      _emit();
    });
    return _writes;
  }

  Future<void> flush() async {
    await _binding;
    if (!_recordsReady) await _readAgain();
    await _retryPending();
    // The place is saved first. The kept page is derived from it.
    _keepShown();
    await _keeping;
  }

  Future<void> refreshPersonalRecords() async {
    await flush();
    final account = _account;
    if (account == null ||
        !_recordsReady ||
        _pendingWrites.containsKey(account)) {
      return;
    }
    final revision = _recordRevision;
    final generation = _accountGeneration;
    final saved = await store.read(account);
    if (saved == null ||
        !_liveAccount(generation) ||
        account != _account ||
        revision != _recordRevision) {
      return;
    }
    final resumes = (saved['resumes'] as List)
        .map(
          (value) =>
              decodeTextPosition(Map<String, dynamic>.from(value as Map)),
        )
        .toList();
    final bookmarks = (saved['bookmarks'] as List)
        .map(
          (value) => Bookmark.fromJson(
            Map<String, dynamic>.from(value as Map),
            decodeTextPosition,
          ),
        )
        .toList();
    _resumes
      ..clear()
      ..addAll(resumes);
    _bookmarks = bookmarks;
    _history = _moves(saved);
    _undo = _history.where((event) => event.id == _undo?.id).firstOrNull;
    store.acceptSnapshot(account, saved);
    _emit();
  }

  /// The reading moves of the reading [snapshot], newest first. A snapshot
  /// without moves, as stores before reading history give, has none.
  static List<HistoryEvent<TextPosition>> _moves(
    Map<String, dynamic> snapshot,
  ) => [
    for (final value in snapshot['history'] as List? ?? const [])
      HistoryEvent.fromJson(
        Map<String, dynamic>.from(value as Map),
        decodeTextPosition,
      ),
  ]..sort((first, second) => second.at.compareTo(first.at));

  /// Throws a [StateError] when an invariant of the class comment does not
  /// hold. It runs on demand, in every build.
  void checkInvariants() {
    if ((_account == null &&
            (document != null ||
                _bookmarks.isNotEmpty ||
                _history.isNotEmpty ||
                _resumes.isNotEmpty ||
                _pdfBooks.isNotEmpty)) ||
        (document != null && (edition == null || !_current(edition!))) ||
        (_bookMap != null && document == null) ||
        (_navigator != null && document == null) ||
        (_pager != null && document is! EpubDocument) ||
        (_keptPage != null &&
            (_pager?.shown.value != null || !_loading && _pager == null)) ||
        (document is EpubDocument && !_loading && _pager == null) ||
        (position != null && _compatible(position!) == null) ||
        ((_visibleAddress == null) != (position == null)) ||
        (_visibleAddress != null &&
            jsonEncode(_compatible(position!)?.toJson()) !=
                jsonEncode(_visibleAddress!.toJson())) ||
        _failedAccounts.any((key) => !_pendingWrites.containsKey(key)) ||
        (_recordsReady && _unreadChanges.containsKey(_account)) ||
        (_undo != null && !_history.contains(_undo)) ||
        (_pending != null && (_pending!.token != token || edition == null)) ||
        (_landed != null && _landed!.after.editionId != edition?.id)) {
      throw StateError(
        'Reading state must belong to one current account, source, and processed publication.',
      );
    }
    _pager?.checkInvariants();
  }

  /// Notifies each signal whose part changed, then the session once if any
  /// part changed.
  void _emit() {
    if (_disposed) return;
    var changed = false;
    for (final signal in _signals) {
      if (signal.publish()) changed = true;
    }
    if (changed) notifyListeners();
  }

  @override
  void dispose() {
    _unregisterWriter?.call();
    _disposed = true;
    speed?.charactersPerMinute.removeListener(_emit);
    _clear();
    unawaited(_retryPending());
    for (final signal in _signals) {
      signal.dispose();
    }
    previews.dispose();
    super.dispose();
  }
}

/// The contents that the session lists for [publication], as
/// [listedContents] gives them. A large package document is read in
/// another isolate.
Future<List<ContentsEntry>> _contentsOf(Publication publication) async {
  if (publication.contents.isNotEmpty) return publication.contents;
  final package = publication.textFiles[publication.packagePath]!;
  // NOTE: A hop costs a few milliseconds, more than reading a small package
  // document.
  final linear = package.length < 64 << 10
      ? linearSpine(package)
      : await compute(linearSpine, package);
  return spineContents(publication, linear);
}

/// What [ReaderSession.message] says when a place to go to cannot be
/// found in the open book or in another ebook edition of it.
const _unknownPlace =
    'This place belongs to different source or processed content and cannot be applied.';

/// A jump that a session asked for, or the open of a book, whose place has
/// not shown yet.
class _Move {
  _Move(
    this.kind,
    this.before, {
    required this.token,
    this.shown,
    this.end,
    this.device,
    this.counterpart,
  });
  final HistoryAction kind;

  /// The place that showed when the jump began, or for an open that starts
  /// a visit elsewhere, this phone's own last place in the edition. Null for
  /// the start of a visit, which begins where it ends.
  final TextPosition? before;

  /// The name of the device that saved the place where an open ends.
  final String? device;

  /// For a mapped move, the place of the other edition that it goes to the
  /// landing of, and how Bookfin found the landing.
  final _Counterpart? counterpart;

  /// The address and the last place of the page that showed when the jump
  /// began, or null when that page belongs to another book.
  final ReaderAddress? shown;
  final BookPlace? end;

  /// The [ReaderSession.token] of the book where the jump ends.
  final int token;
}

/// The place of another edition that a mapped move went to the landing of,
/// and how Bookfin found the landing.
typedef _Counterpart = ({Place place, MatchedBy matchedBy});

/// The text size of an account that has not used the size buttons.
const _defaultFontSize = 20.0;

/// The change signal of one part of the session's visible state.
class _Signal extends ChangeNotifier {
  _Signal(this._read) : _published = _read();

  /// Reads the part's state as a value that is `==` to an earlier value
  /// exactly when the part did not change.
  final Object? Function() _read;
  Object? _published;

  /// Notifies if the part changed since the last call, and says whether it
  /// did.
  bool publish() {
    final state = _read();
    if (state == _published) return false;
    _published = state;
    notifyListeners();
    return true;
  }
}
