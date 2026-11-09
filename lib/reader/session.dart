import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_epub_viewer/publication.dart';
import 'package:flutter_epub_viewer/navigation.dart';
import 'package:xml/xml_events.dart';

import '../catalog/jellyfin.dart';
import '../catalog/model.dart';
import '../downloads/downloads.dart';
import '../playback/playback.dart';
import 'book_map.dart';
import 'document.dart';
import 'epub/pager.dart';
import 'page_previews.dart';
import 'pdf.dart';

export 'package:flutter_epub_viewer/navigation.dart';

typedef PublicationLoader = Future<Publication> Function(Uri uri);
typedef DocumentLoader = Future<ReaderDocument> Function(
  Uri uri,
  SourceFile source,
);
typedef VisibleLocation = ReadingLocation;

/// The owner of each account's saved reading records, as [ReaderSession]
/// uses it.
abstract class ReadingStore {
  /// The saved reading snapshot of [accountKey], or null when the account
  /// has none: `version`, `fontSize`, `resumes` and `bookmarks`.
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

  /// Whether this store found the saved records of [accountKey] damaged
  /// while this app ran, kept the damaged data aside, and started the
  /// account again from the records that it could read. A [read] of the
  /// account finds out.
  bool setAside(String accountKey) => false;
}

/// The reading records that one save changes.
///
/// A save carries the whole small [settings], but only the resumes and
/// bookmarks that changed.
class ReadingChanges {
  ReadingChanges(
    this.settings, {
    this.resumes = const [],
    this.bookmarks = const {},
  });

  /// The version and the font size.
  final Map<String, dynamic> settings;

  /// The changed resumes as JSON. A resume replaces the saved resume of the
  /// same edition, source and revision. Resumes are never deleted.
  final List<Map<String, dynamic>> resumes;

  /// The changed bookmarks as JSON, by id. A null value deletes it.
  final Map<String, Map<String, dynamic>?> bookmarks;

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
  );

  /// The reading snapshot that results when these changes apply to
  /// [snapshot]. A changed resume goes last, as the session orders its
  /// places. A changed bookmark keeps its place, a new one goes last, and a
  /// deleted one is removed.
  Map<String, dynamic> applyTo(Map<String, dynamic>? snapshot) {
    final unplaced = Map.of(bookmarks);
    return {
      ...settings,
      'resumes': [
        for (final value in snapshot?['resumes'] as List? ?? const [])
          if (!resumes.any((next) => _samePlace(value as Map, next)))
            Map<String, dynamic>.from(value as Map),
        ...resumes,
      ],
      'bookmarks': [
        for (final value in snapshot?['bookmarks'] as List? ?? const [])
          if (!unplaced.containsKey(value['id']))
            Map<String, dynamic>.from(value as Map)
          else
            ?unplaced.remove(value['id']),
        ...unplaced.values.nonNulls,
      ],
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
/// - The visible address and the saved position are both set or both
///   absent. The position fits the open document, and its saved form
///   restores the visible address.
/// - Every account whose save failed still has its changes pending.
class ReaderSession extends ChangeNotifier {
  ReaderSession({
    required this.downloads,
    required this.store,
    required this.load,
    this.loadDocument,
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
      _searchChanges = _Signal(() => (_searching, _hits, _searchError)),
      _fontSizeChanges = _Signal(() => _fontSize),
      _saveStatusChanges = _Signal(() => saveFailed),
      _reflowChanges = _Signal(() => _reflow),
      _bookMapChanges = _Signal(() => _bookMap),
    ];
  }
  final Downloads downloads;
  final ReadingStore store;
  final PublicationLoader load;
  final DocumentLoader? loadDocument;
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
  double _fontSize = 20;
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
  List<TextBookmark> _bookmarks = const [];
  bool _disposed = false;
  bool _recordsReady = false;
  int _accountGeneration = 0;
  Future<void> _binding = Future.value();
  Future<void> _writes = Future.value();
  final _pendingWrites = <String, ReadingChanges>{};
  final _failedAccounts = <String>{};
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

  /// Notifies when [searching], [hits] or [searchError] changes.
  Listenable get searchChanges => _searchChanges;

  /// Notifies when [fontSize] changes.
  Listenable get fontSizeChanges => _fontSizeChanges;

  /// Notifies when [saveFailed] changes.
  Listenable get saveStatusChanges => _saveStatusChanges;

  /// Whether the account has reading records that the store did not accept.
  /// The session keeps them and retries on each later write or [flush].
  bool get saveFailed => _failedAccounts.contains(_account);
  late final _Signal _placeChanges;
  late final _Signal _documentChanges;
  late final _Signal _bookmarkChanges;
  late final _Signal _searchChanges;
  late final _Signal _fontSizeChanges;
  late final _Signal _saveStatusChanges;
  late final _Signal _bookMapChanges;
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
  /// contents.
  BookMap? get bookMap => _bookMap;

  /// Notifies when [bookMap] changes.
  Listenable get bookMapChanges => _bookMapChanges;

  /// The place of [bookmark] in the open book, or null when the bookmark
  /// belongs to other content.
  ReaderAddress? addressOf(TextBookmark bookmark) =>
      _compatible(bookmark.position);

  bool get ready => document != null && _navigator != null;
  bool get canBookmark => _recordsReady && position != null;
  List<TextBookmark> get bookmarks => List.unmodifiable(
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
      await _retryPending();
      return;
    }
    _account = account?.scope.key;
    _credential = account?.token;
    _clear();
    _resumes.clear();
    _bookmarks = const [];
    _recordsReady = false;
    _fontSize = 20;
    final generation = ++_accountGeneration;
    final key = _account;
    final previous = _binding;
    _binding = () async {
      await previous;
      await _retryPending();
      if (!_liveAccount(generation) || key == null) return;
      try {
        final pending = _pendingWrites[key];
        final stored = await store.read(key);
        final saved = pending == null ? stored : pending.applyTo(stored);
        if (!_liveAccount(generation)) return;
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
                (value) => TextBookmark.fromJson(value as Map<String, dynamic>),
              )
              .toList();
          if (bookmarks.map((mark) => mark.id).toSet().length !=
              bookmarks.length) {
            throw const FormatException('Duplicate reading bookmarks.');
          }
          _resumes.addAll(resumes);
          _bookmarks = bookmarks;
          final size = saved['fontSize'];
          if (size is num && size.isFinite) {
            _fontSize = size.toDouble().clamp(14, 40);
          }
        }
        if (pending == null) store.acceptSnapshot(key, saved);
        _recordsReady = true;
      } on Exception {
        if (_liveAccount(generation)) _message = 'Reading records could not be opened. Existing records were kept. Restart before saving new places.';
      }
      _emit();
    }();
    _emit();
    await _binding;
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
    ++_token;
    ++_search;
    previews.close();
    _navigator = null;
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
  }

  Future<void> open(Book book, Edition selected) async {
    if (_disposed || _account == null || !_current(selected)) return;
    _clear();
    _book = book;
    _edition = selected;
    _loading = true;
    final generation = token;
    _emit();
    await _binding;
    if (!_live(generation) || !_current(selected)) return;
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
      final admitted = await downloads.readLocalFile<ReaderDocument>(
        selected.files.single,
        (uri) async {
          if (uri.scheme != 'file') {
            throw const FormatException(
              'The reader requires a verified local download.',
            );
          }
          return loadDocument == null
              ? EpubDocument(await load(uri))
              : await loadDocument!(uri, selected.files.single);
        },
      );
      if (admitted == null) {
        throw const FormatException(
          'Download this ebook before reading. Only verified local files can open.',
        );
      }
      if (!_live(generation) || !_current(selected)) {
        await admitted.dispose();
        return;
      }
      _document = admitted;
      if (admitted is PdfBook) {
        // A recognized page that started saves its text after this book
        // closes, so only the download and the catalog decide whether its
        // original can be read, not whether the book is still open.
        bool available() => !_disposed && _current(selected);
        admitted.textSupply?.bind((read) async {
          if (!available()) return null;
          bool Function() owned = () => true;
          return downloads.readLocalFile<PdfText>(selected.files.single, (
            uri,
          ) async {
            if (!available()) {
              return const PdfText(
                source: '',
                text: '',
                sourceOffsets: [],
                status: PdfTextStatus.absent,
              );
            }
            return read(uri, () => owned() && available());
          }, onOwnership: (live) => owned = live);
        });
      }
      final candidates = _resumes
          .where((value) => value.editionId == selected.id)
          .toList();
      final saved =
          candidates.where((value) => _compatible(value) != null).lastOrNull ??
          candidates.lastOrNull;
      if (saved != null) {
        _initialAddress = _compatible(saved);
        if (initialAddress == null) {
          _message = 'The saved place belongs to different source or processed content. The old place and bookmarks were kept. Reading starts at the beginning.';
        }
      }
      if (!_recordsReady) {
        _message = 'Reading records could not be opened. Existing records were kept. Restart before saving new places.';
      } else if (store.setAside(_account!)) {
        _message ??= 'Saved reading records were damaged. Bookfin kept a copy and restored the places that it could read. The next sync restores the rest.';
      }
      if (admitted is EpubDocument) {
        final contents = await _contentsOf(admitted.publication);
        if (!_live(generation)) return;
        final pager = _pager = EpubPager(
          admitted,
          initial: _initialAddress,
          onPlace: (address) => acceptAddress(generation, address),
          onWarning: (message) => warn(generation, message),
        );
        attachDocument(generation, pager, contents);
      }
    } on FormatException catch (error) {
      if (_live(generation)) _message = error.message;
    } catch (_) {
      if (_live(generation)) _message = 'The downloaded ebook could not be opened. Check the download, then retry.';
    } finally {
      if (_live(generation)) {
        _loading = false;
        _emit();
      }
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

  void attach(
    int eventToken,
    NavigatorPort navigator,
    List<ContentsEntry> entries,
  ) {
    attachDocument(eventToken, EpubNavigator(navigator), entries);
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
    _bookMap = map;
    _emit();
  }

  void failed(int eventToken, String explanation) {
    if (!_live(eventToken)) return;
    _navigator = null;
    _message = explanation;
    _emit();
  }

  void warn(int eventToken, String explanation) {
    if (!_live(eventToken)) return;
    _message = explanation;
    _emit();
  }

  void closeView(int eventToken) {
    if (_live(eventToken)) _clear();
  }

  void acceptVisible(int eventToken, VisibleLocation location) =>
      acceptAddress(eventToken, EpubAddress(location));

  void acceptAddress(int eventToken, ReaderAddress address) {
    final admitted = document;
    if (!_live(eventToken) ||
        admitted == null ||
        edition == null ||
        !admitted.accepts(address)) {
      return;
    }
    try {
      admitted.decodeAddress(address.toJson());
    } catch (_) {
      return;
    }
    _visibleAddress = address;
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
    unawaited(_save(resumes: [position!]));
    _emit();
  }

  Future<void> addBookmark({String? title, String? note}) async {
    final current = position;
    if (current == null || !_recordsReady) return;
    final added = TextBookmark(
      id: recordId(),
      position: current,
      createdAt: DateTime.now(),
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
    final edited = TextBookmark(
      id: old.id,
      position: old.position,
      createdAt: old.createdAt,
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

  Future<void> restoreBookmark(String id) async {
    final saved = _bookmarks.where((value) => value.id == id).firstOrNull;
    if (saved == null || _navigator == null) return;
    final location = _compatible(saved.position);
    if (location == null) {
      _message = 'This bookmark belongs to different source or processed content and cannot be applied.';
      _emit();
      return;
    }
    await _navigate(() => _navigator!.display(location));
  }

  Future<void> _navigate(Future<void> Function() action) async {
    final generation = token;
    try {
      await action();
    } catch (_) {
      if (_live(generation)) {
        _message = 'The reading destination could not be opened. Your saved place was kept.';
        _emit();
      }
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
    final map = _bookMap;
    if (map == null || map.chapters.isEmpty) return move(forward);
    final place = _visibleAddress;
    final start = place == null
        ? null
        : map.chapterStep(place, forward: forward, end: _pager?.shownEnd);
    if (start != null) await goTo(map.targetAt(start));
  }

  /// Shows [target], a place that the scrub bar chose in the open book. The
  /// viewport then reports the page that it shows, which becomes the visible
  /// place and is saved like a page turn. If the viewport cannot show it,
  /// the place stays and [message] says so.
  Future<void> goTo(BookTarget target) async {
    final navigator = _navigator;
    if (navigator != null) {
      await _navigate(() => navigator.seek(target.part, target.progress));
    }
  }

  Future<void> goToContents(String href) async {
    final navigator = _navigator;
    if (navigator != null) await _navigate(() => navigator.contents(href));
  }

  bool _reflow = false;
  late final _Signal _reflowChanges;

  /// Whether PDF pages show as reflowed text instead of the original page.
  /// The choice lasts for this run of the app, through closing and opening
  /// books and accounts. It is not saved in the reading records, so a new
  /// session starts on the original page.
  bool get reflow => _reflow;

  /// Notifies when [reflow] changes.
  Listenable get reflowChanges => _reflowChanges;

  void setReflow(bool on) {
    _reflow = on;
    _emit();
  }

  Future<void> setFontSize(double size) async {
    if (!size.isFinite) return;
    _fontSize = size.clamp(14, 40);
    await _save();
    _emit();
  }

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
    final navigator = _navigator;
    if (navigator != null && hits.contains(hit)) {
      await _navigate(() => navigator.display(hit.address));
    }
  }

  /// Hands the store the [resumes] and [bookmarks] that one action changed,
  /// with the current settings. A null bookmark is a deletion. The changes
  /// stay pending, merged with earlier pending changes, until the store
  /// saves them.
  Future<void> _save({
    List<TextPosition> resumes = const [],
    Map<String, TextBookmark?> bookmarks = const {},
  }) async {
    final key = _account;
    if (key == null || !_recordsReady || _disposed) return;
    ++_recordRevision;
    final changes = ReadingChanges(
      {'version': 1, 'fontSize': fontSize},
      resumes: resumes.map(encodeTextPosition).toList(),
      bookmarks: {
        for (final MapEntry(key: id, value: mark) in bookmarks.entries)
          id: mark?.toJson(),
      },
    );
    _pendingWrites[key] = _pendingWrites[key]?.followedBy(changes) ?? changes;
    await _retryPending();
  }

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
    await _retryPending();
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
          (value) =>
              TextBookmark.fromJson(Map<String, dynamic>.from(value as Map)),
        )
        .toList();
    _resumes
      ..clear()
      ..addAll(resumes);
    _bookmarks = bookmarks;
    store.acceptSnapshot(account, saved);
    _emit();
  }

  /// Throws a [StateError] when an invariant of the class comment does not
  /// hold. It runs on demand, in every build.
  void checkInvariants() {
    if ((_account == null &&
            (document != null ||
                _bookmarks.isNotEmpty ||
                _resumes.isNotEmpty)) ||
        (document != null && (edition == null || !_current(edition!))) ||
        (_bookMap != null && document == null) ||
        (_navigator != null && document == null) ||
        (_pager != null && document is! EpubDocument) ||
        (document is EpubDocument && !_loading && _pager == null) ||
        (position != null && _compatible(position!) == null) ||
        ((_visibleAddress == null) != (position == null)) ||
        (_visibleAddress != null &&
            jsonEncode(_compatible(position!)?.toJson()) !=
                jsonEncode(_visibleAddress!.toJson())) ||
        _failedAccounts.any((key) => !_pendingWrites.containsKey(key))) {
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
    _disposed = true;
    _clear();
    unawaited(_retryPending());
    for (final signal in _signals) {
      signal.dispose();
    }
    previews.dispose();
    super.dispose();
  }
}

/// The contents that the session lists for [publication]: its own, or, when
/// it has none, one "Chapter N" entry for each linear section of its spine,
/// as the WebView reader listed them (reader.js). Each href is relative to
/// the package document's directory, as contents hrefs are.
Future<List<ContentsEntry>> _contentsOf(Publication publication) async {
  if (publication.contents.isNotEmpty) return publication.contents;
  final package = publication.resources[publication.packagePath]!;
  // NOTE: A hop costs a few milliseconds, more than reading a small package
  // document.
  final linear = package.length < 64 << 10
      ? _linearSpine(package)
      : await compute(_linearSpine, package);
  final directory = publication.packagePath.split('/')..removeLast();
  String relative(String path) {
    final parts = path.split('/');
    var shared = 0;
    while (shared < directory.length &&
        shared < parts.length - 1 &&
        directory[shared] == parts[shared]) {
      shared++;
    }
    return [
      for (var up = shared; up < directory.length; up++) '..',
      ...parts.skip(shared).map(Uri.encodeComponent),
    ].join('/');
  }

  final sections = [
    for (final (index, path) in publication.spine.indexed)
      if (index < linear.length && linear[index]) path,
  ];
  return List.unmodifiable([
    for (final (index, path) in sections.indexed)
      ContentsEntry('Chapter ${index + 1}', relative(path)),
  ]);
}

/// Whether each spine item of the package document [package] is linear, in
/// spine order. As in epub.js, an item is linear unless its `linear`
/// attribute has a value other than `yes`.
List<bool> _linearSpine(Uint8List package) => [
  for (final event in parseEvents(utf8.decode(package)))
    if (event case XmlStartElementEvent(
      localName: 'itemref',
      :final attributes,
    ))
      switch (attributes
          .where((attribute) => attribute.localName == 'linear')
          .firstOrNull
          ?.value) {
        null || '' || 'yes' => true,
        _ => false,
      },
];

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
