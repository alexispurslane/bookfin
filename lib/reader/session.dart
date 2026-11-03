import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_epub_viewer/publication.dart';
import 'package:flutter_epub_viewer/navigation.dart';

import '../catalog/jellyfin.dart';
import '../catalog/model.dart';
import '../downloads/downloads.dart';
import '../playback/playback.dart';
import 'document.dart';

export 'package:flutter_epub_viewer/navigation.dart';

typedef PublicationLoader = Future<Publication> Function(Uri uri);
typedef DocumentLoader = Future<ReaderDocument> Function(
  Uri uri,
  SourceFile source,
);
typedef VisibleLocation = ReadingLocation;

class ReaderSession extends ChangeNotifier {
  ReaderSession({
    required this.downloads,
    required this.store,
    required this.load,
    this.loadDocument,
  });
  final Downloads downloads;
  final ResumeStore store;
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
  String? _account;
  String? _credential;
  List<Book> _books = [];
  final List<TextPosition> _resumes = [];
  final List<TextBookmark> _bookmarks = [];
  bool _disposed = false;
  bool _recordsReady = false;
  int _accountGeneration = 0;
  Future<void> _binding = Future.value();
  Future<void> _writes = Future.value();
  final _pendingWrites = <String, Map<String, dynamic>>{};
  final _failedAccounts = <String>{};
  int _search = 0;
  int _recordRevision = 0;

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
    _bookmarks.clear();
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
        final saved = pending ?? await store.read(key);
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
          _bookmarks.addAll(bookmarks);
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
    _navigator = null;
    final previous = _document;
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
      final uri = await downloads.localFile(selected.files.single);
      if (!_live(generation)) return;
      if (uri == null || uri.scheme != 'file') {
        throw const FormatException(
          'Download this ebook before reading. Only verified local files can open.',
        );
      }
      final admitted = loadDocument == null
          ? EpubDocument(await load(uri))
          : await loadDocument!(uri, selected.files.single);
      if (!_live(generation) || !_current(selected)) {
        await admitted.dispose();
        return;
      }
      _document = admitted;
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
      if (!_recordsReady) _message = 'Reading records could not be opened. Existing records were kept. Restart before saving new places.';
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
    unawaited(_save());
    _emit();
  }

  Future<void> addBookmark({String? title, String? note}) async {
    final current = position;
    if (current == null || !_recordsReady) return;
    _bookmarks.add(
      TextBookmark(
        id: recordId(),
        position: current,
        createdAt: DateTime.now(),
        title: title,
        note: note,
      ),
    );
    await _save();
    _emit();
  }

  Future<void> editBookmark(String id, {String? title, String? note}) async {
    final index = _bookmarks.indexWhere((value) => value.id == id);
    if (index < 0) return;
    final old = _bookmarks[index];
    _bookmarks[index] = TextBookmark(
      id: old.id,
      position: old.position,
      createdAt: old.createdAt,
      title: title,
      note: note,
    );
    await _save();
    _emit();
  }

  Future<void> deleteBookmark(String id) async {
    _bookmarks.removeWhere((value) => value.id == id);
    await _save();
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

  Future<void> goToContents(String href) async {
    final navigator = _navigator;
    if (navigator != null) await _navigate(() => navigator.contents(href));
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

  Future<void> _save() async {
    final key = _account;
    if (key == null || !_recordsReady || _disposed) return;
    ++_recordRevision;
    final value = <String, dynamic>{
      'version': 1,
      'fontSize': fontSize,
      'resumes': _resumes.map(encodeTextPosition).toList(),
      'bookmarks': _bookmarks.map((value) => value.toJson()).toList(),
    };
    _pendingWrites[key] = value;
    await _retryPending();
  }

  Future<void> _retryPending() {
    _writes = _writes.then((_) async {
      for (final entry in _pendingWrites.entries.toList()) {
        try {
          await store.write(entry.key, entry.value);
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
    _bookmarks
      ..clear()
      ..addAll(bookmarks);
    store.acceptSnapshot(account, saved);
    _emit();
  }

  void checkInvariants() {
    if ((_account == null &&
            (document != null ||
                _bookmarks.isNotEmpty ||
                _resumes.isNotEmpty)) ||
        (document != null && (edition == null || !_current(edition!))) ||
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
  }

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _clear();
    unawaited(_retryPending());
    super.dispose();
  }
}
