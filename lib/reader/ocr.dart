import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart';

import '../downloads/downloads.dart';
import '../foundation/hop.dart';
import 'ocr_storage.dart';
import 'page_geometry.dart';
import 'pdf.dart';

/// The recognized text of a page with its words, and whether its cache file
/// holds the recognition output.
typedef _Recognized = ({PdfText text, RecognizedWords words, bool saved});

/// A page's text for reading, with the words that recognition found on it.
/// A text that recognition did not give has no words.
typedef _Read = ({PdfText text, RecognizedWords words});

_Read _only(PdfText text) => (text: text, words: RecognizedWords.none);

/// The one owner of English page recognition while Bookfin runs. Android
/// has one native recognition worker, so the work of every open PDF waits
/// in this one queue. No reader and no widget owns work that runs.
///
/// A page has two kinds of work: its layout pass, which gives its words,
/// and its recognition, which gives its text. The page that a reader shows
/// asks for a layout pass, so a layout pass goes to the front of the queue.
/// The recognition of a page whose layout pass waits or runs goes right
/// behind that layout pass. Other recognition waits in the order of its
/// requests. A background layout pass, which the book survey asks for,
/// waits behind all other work. A reader's request for the same page moves
/// it to the front, and a request for the page's recognition moves it right
/// before that recognition.
///
/// The native engine keeps the image of its last layout pass, and
/// recognition can reuse that image. This queue alone calls the native
/// worker, and it runs one piece of work at a time, so it knows the page
/// whose image the engine keeps ([_kept]). Recognition reuses the kept image
/// only when the last native call was the layout pass of the same page.
/// Otherwise it draws and sends its page again. So recognition never reads
/// the image of another page.
///
/// Work that starts always finishes and saves its result in the cache,
/// whether or not a reader still waits for it. A reader that turns the
/// page, cancels, closes the book or leaves the app only stops waiting.
/// Work that has not started leaves the queue when its last reader stops
/// waiting. The native worker closes when no reader holds it and no work
/// waits or runs.
///
/// Invariants: at most one piece of work runs, and it is not among the
/// waiting work; every waiting piece has a reader that waits for it;
/// [_jobs] holds exactly the waiting and the running work; no recognition
/// waits before the waiting layout pass of its page; background work waits
/// behind all other work; no work runs and the engine keeps no page while
/// the native worker closes.
class EnglishRecognition {
  EnglishRecognition._();
  static final instance = EnglishRecognition._();
  static const _channel = MethodChannel('bookfin/ocr');
  final Map<String, _Job<Object?>> _jobs = {};
  final List<_Job<Object?>> _waiting = [];
  _Job<Object?>? _running;
  int _holders = 0;
  Future<void>? _closing;

  /// The page whose image the native engine keeps: the page of the last
  /// native call, when that call was a layout pass that succeeded.
  String? _kept;

  /// Whether the work saved under [key] waits or runs.
  bool _has(String key) => _jobs.containsKey(key);

  /// How many pieces of work wait, for tests that order requests.
  @visibleForTesting
  int get debugWaiting => _waiting.length;

  /// Waits for the work saved under [key]: the layout pass of [page] when
  /// [layout] holds, and otherwise its recognition. If that work does not
  /// wait or run, [run] runs it in its place in the queue. A layout pass
  /// that waits moves to the front again, unless this wait is [background].
  /// Only a layout pass can be background work. [run] must claim what it
  /// needs before its first await, because the reader can stop waiting at
  /// any later moment.
  _Wait<T> _wait<T>(
    String key,
    String page,
    Future<T> Function() run, {
    bool layout = false,
    bool background = false,
  }) {
    assert(_holders > 0, 'A reader that waits holds the native worker.');
    assert(layout || !background, 'Only a layout pass waits in background.');
    var job = _jobs[key] as _Job<T>?;
    if (job == null) {
      job = _Job<T>(key, page, layout, run)..background = background;
      _jobs[key] = job;
      _place(job);
    } else if (layout && !background && _waiting.remove(job)) {
      job.background = false;
      _place(job);
    }
    final wait = _Wait<T>(this, job);
    job.waits.add(wait);
    _start();
    return wait;
  }

  /// Puts the waiting [job] in its place in the queue.
  void _place(_Job<Object?> job) {
    bool samePage(_Job<Object?> other) => other.page == job.page;
    if (job.background) {
      _waiting.add(job);
      return;
    }
    if (job.layout) {
      _waiting.insert(0, job);
      final text = _waiting.indexWhere(
        (other) => !other.layout && samePage(other),
      );
      if (text > 1) _waiting.insert(1, _waiting.removeAt(text));
      return;
    }
    final running = _running;
    var layout = _waiting.indexWhere(
      (other) => other.layout && samePage(other),
    );
    if (layout >= 0 && _waiting[layout].background) {
      // The page's background layout pass moves to the place of this
      // recognition, so that the recognition still reuses its image.
      final pass = _waiting.removeAt(layout)..background = false;
      layout = _foregroundEnd();
      _waiting.insert(layout, pass);
    }
    if (layout >= 0) {
      _waiting.insert(layout + 1, job);
    } else if (running != null && running.layout && samePage(running)) {
      _waiting.insert(0, job);
    } else {
      _waiting.insert(_foregroundEnd(), job);
    }
  }

  /// The index of the first waiting background work, or the queue's length.
  int _foregroundEnd() {
    final index = _waiting.indexWhere((job) => job.background);
    return index < 0 ? _waiting.length : index;
  }

  void _leave(_Wait<Object?> wait) {
    final job = wait.job;
    if (!job.waits.remove(wait)) return;
    wait.result.complete(null);
    if (job.waits.isEmpty && !identical(job, _running)) {
      // A reader that waits holds the worker, so its close follows later.
      _waiting.remove(job);
      _jobs.remove(job.key);
    }
  }

  void _start() {
    if (_running != null || _closing != null || _waiting.isEmpty) return;
    final job = _running = _waiting.removeAt(0);
    unawaited(_finish(job));
  }

  Future<void> _finish(_Job<Object?> job) async {
    try {
      await job.execute();
    } finally {
      _jobs.remove(job.key);
      _running = null;
      _start();
      // A close failure that no closing book waits for is not reported. The
      // next page opens a new worker, and native recognition refuses an
      // unsafe one.
      unawaited(_closeIfIdle().catchError((Object _) {}));
    }
  }

  /// Runs the layout pass on [raster], the image of [page], and gives its
  /// layout record (see native/ocr/bookfin_ocr.c). The engine keeps the
  /// image. Only the running work of [page] calls it.
  Future<Int32List> _layout(String page, PdfRaster raster) async {
    assert(
      _running?.page == page,
      'Only the running work of a page calls the native worker.',
    );
    _kept = null;
    final record = await _channel.invokeMethod<Int32List>(
      'layout',
      _image(raster),
    );
    if (record == null) {
      throw PlatformException(
        code: 'recognition',
        message: 'The layout pass gave no record.',
      );
    }
    _kept = page;
    return record;
  }

  /// Recognizes [page] and gives its hOCR. It reuses the image that the
  /// engine keeps when the last native call was the layout pass of [page].
  /// Otherwise [render] draws the page, before the first await. Only the
  /// running work of [page] calls it.
  Future<String> _recognize(
    String page,
    Future<PdfRaster> Function() render,
  ) async {
    assert(
      _running?.page == page,
      'Only the running work of a page calls the native worker.',
    );
    if (_kept == page) {
      _kept = null;
      return await _channel.invokeMethod<String>('recognize') ?? '';
    }
    _kept = null;
    final raster = await render();
    return await _channel.invokeMethod<String>('recognize', _image(raster)) ??
        '';
  }

  static Map<String, Object> _image(PdfRaster raster) => {
    'width': raster.width,
    'height': raster.height,
    'bgra': raster.bgra,
  };

  /// Keeps the native worker open until [_release].
  void _hold() => _holders++;

  /// Ends a hold. The native worker closes now if nothing else uses it, and
  /// the result reports that close. Otherwise it closes after the last
  /// page, and the result completes at once.
  Future<void> _release({required bool held}) {
    assert(!held || _holders > 0);
    if (held) _holders--;
    return _closeIfIdle();
  }

  Future<void> _closeIfIdle() {
    if (_holders > 0 || _running != null || _waiting.isNotEmpty) {
      return Future.value();
    }
    return _closing ??= () async {
      _kept = null; // The close frees the engine and its image.
      try {
        await _channel.invokeMethod<void>('close');
      } finally {
        _closing = null;
        _start();
      }
    }();
  }

  void checkInvariants() {
    final running = _running;
    bool layoutAfter(int index) => _waiting
        .skip(index + 1)
        .any((other) => other.layout && other.page == _waiting[index].page);
    if (_holders < 0 ||
        running != null && _waiting.contains(running) ||
        _waiting.any((job) => job.waits.isEmpty) ||
        _jobs.length != _waiting.length + (running == null ? 0 : 1) ||
        _waiting.any((job) => !identical(_jobs[job.key], job)) ||
        running != null && !identical(_jobs[running.key], running) ||
        [
          for (final (index, job) in _waiting.indexed)
            if (!job.layout && layoutAfter(index)) job,
        ].isNotEmpty ||
        _waiting
            .skipWhile((job) => !job.background)
            .any((job) => !job.background) ||
        _waiting.any((job) => job.background && !job.layout) ||
        _closing != null && (running != null || _kept != null)) {
      throw StateError(
        'Recognition must run at most one piece of work, keep only waited-for work waiting, put a page\'s layout pass before its recognition, and never run work or keep a page while the native worker closes.',
      );
    }
  }
}

/// One piece of work of [EnglishRecognition]: the layout pass or the
/// recognition of one page, with the readers that wait for it.
class _Job<T> {
  _Job(this.key, this.page, this.layout, this.run);

  /// The key that the work's result has in the cache.
  final String key;

  /// The page that the work reads: the key of its recognition output.
  final String page;

  /// Whether the work is a layout pass, and not recognition.
  final bool layout;

  /// Whether the work waits behind all other work. Only a layout pass that
  /// only the book survey waits for is background work.
  bool background = false;
  final Future<T> Function() run;
  final Set<_Wait<T>> waits = {};

  /// Runs the work and gives its result, or its failure, to every reader
  /// that still waits.
  Future<void> execute() async {
    try {
      final value = await run();
      for (final wait in waits) {
        wait.result.complete(value);
      }
    } catch (error, stack) {
      // A failure that no reader waits for has nobody to tell. The work runs
      // again when a reader next opens the page.
      for (final wait in waits) {
        wait.result.completeError(error, stack);
      }
    } finally {
      waits.clear();
    }
  }
}

/// One reader's wait for one piece of work. Its result is null when the
/// reader stopped waiting.
class _Wait<T> {
  _Wait(this._owner, this.job);
  final EnglishRecognition _owner;
  final _Job<T> job;
  final result = Completer<T?>();
  void leave() => _owner._leave(this);
}

class BundledEnglishText implements PdfTextSupply {
  /// Recognizes English text on scanned pages, and finds their words with
  /// Tesseract's layout pass. Each recognized page and each layout record,
  /// new or cached, is decoded through `hop`, and text attaches to words
  /// through `hop`. Work runs in [EnglishRecognition.instance], so work
  /// that started finishes and is saved after this reader stops waiting or
  /// closes.
  BundledEnglishText({this._hop = compute});
  final IsolateHop _hop;
  static const version =
      'bookfin-ocr-2/tesseract4android-4.9.0/tesseract-5.5.1/leptonica-1.85.0/tessdata_fast-4.1.0-eng-7d4322bd2a7749724879683fc3912cb542f19906c83bcc1a52132556427170b2';
  final _recognition = EnglishRecognition.instance;
  PdfTextLease? _lease;
  int _generation = 0;
  bool _closed = false;
  bool _fatal = false;
  bool _holding = false;

  /// The waits that show as recognition progress ([recognizing]).
  final Set<_Wait<Object?>> _waits = {};

  /// The waits of background layout passes, which show no progress.
  final Set<_Wait<Object?>> _backgroundWaits = {};
  final Map<int, _Recognized> _selected = {};
  _OwnedTextRead? _read;
  final _recognizing = ValueNotifier(false);
  @override
  ValueListenable<bool> get recognizing => _recognizing;
  @override
  void bind(PdfTextLease lease) => _lease = lease;

  /// The keys that name [page] of [book]: its recognition output, which
  /// also names the page in the queue, and its layout record. Hashing two
  /// short strings costs less than a hop to another isolate.
  static ({String text, String layout}) _keys(PdfBook book, int page) => (
    text: sha256
        .convert(utf8.encode('$version/${book.originalDigest}/$page'))
        .toString(),
    layout: sha256
        .convert(
          utf8.encode('bookfin-layout-1/$version/${book.originalDigest}/$page'),
        )
        .toString(),
  );

  /// Stops every wait of this reader. Work that started still finishes and
  /// is saved; work that did not start leaves the queue.
  @override
  void cancel() {
    _generation++;
    final waits = [..._waits, ..._backgroundWaits];
    _waits.clear();
    _backgroundWaits.clear();
    for (final wait in waits) {
      wait.leave();
    }
    if (!_closed) _recognizing.value = false;
  }

  @override
  Future<PdfText> text(PdfBook book, int page, PdfText extracted) async =>
      (await _text(book, page, extracted)).text;

  @override
  Future<({PdfText text, TextAttachment? attachment})> attachedText(
    PdfBook book,
    int page,
    PdfText extracted,
    PageGeometry geometry,
  ) async {
    if (extracted.status == PdfTextStatus.candidate) {
      return (text: extracted, attachment: null);
    }
    final read = await _text(book, page, extracted);
    if (read.text.status != PdfTextStatus.candidate) {
      return (text: read.text, attachment: null);
    }
    final attachment = await _hop(attachText, (
      geometry: geometry,
      words: read.words,
    ));
    return (text: read.text, attachment: attachment);
  }

  Future<_Read> _text(PdfBook book, int page, PdfText extracted) async {
    if (extracted.status == PdfTextStatus.candidate || _closed) {
      return _only(extracted);
    }
    final generation = _generation;
    final key = _keys(book, page).text;
    Future<_Read?> reuse(VerifiedFile original, bool Function() owned) async {
      bool live() => !_closed && generation == _generation && owned();
      if (!live()) return _only(_canceled);
      // Cache access also makes sure that the download still holds this
      // book before this reader reuses its selected text.
      final cached = await readOcrCache(original, book.originalDigest, key);
      if (!live()) return _only(_canceled);
      final selected = _selected[page];
      if (selected != null) {
        return (text: selected.text, words: selected.words);
      }
      if (cached == null) return null;
      final RecognizedPage saved;
      try {
        saved = await _hop(decodeRecognizedPage, cached);
      } on Exception {
        return null; // A cached page that does not decode is recognized again.
      }
      return live()
          ? _select(page, (text: saved.text, words: saved.words, saved: true))
          : _only(_canceled);
    }

    // A page that still runs, perhaps for a reader that left it, is joined.
    // It leaves the queue only after its cache write, so a page that is not
    // found here is already in the cache if it ran.
    if (!_recognition._has(key)) {
      try {
        var available = false;
        final reused = await _withRead((original, owned) async {
          available = true;
          return reuse(original, owned);
        });
        if (!available) return _only(_canceled);
        if (reused != null) return reused;
      } on Exception {
        return _only(_recognitionFailure);
      }
      if (_closed || generation != _generation) return _only(_canceled);
      if (_fatal) return _only(_fatalFallback);
    }
    final lease = _lease;
    if (lease == null) {
      return _only(_failure('Text recognition needs the downloaded book.'));
    }
    _holdWorker();
    final wait = _recognition._wait<_Recognized>(
      key,
      key,
      () => _recognizePage(book, page, key, lease, _hop),
    );
    _waits.add(wait);
    _recognizing.value = true;
    try {
      final recognized = await wait.result.future;
      if (recognized == null || _closed || generation != _generation) {
        return _only(_canceled);
      }
      return _select(page, recognized);
    } on PlatformException catch (error) {
      if (error.code == 'recognition-fatal') {
        _fatal = true;
        return _only(_fatalFallback);
      }
      return _only(_recognitionFailure);
    } on Exception {
      return _only(_recognitionFailure);
    } finally {
      if (_waits.remove(wait) && !_closed) {
        _recognizing.value = _waits.isNotEmpty;
      }
    }
  }

  @override
  Future<PageGeometry?> geometry(
    PdfBook book,
    int page,
    PdfText extracted, {
    bool background = false,
  }) async {
    if (extracted.status == PdfTextStatus.candidate || _closed || _fatal) {
      return null;
    }
    final generation = _generation;
    bool live() => !_closed && generation == _generation;
    final keys = _keys(book, page);
    // A layout pass that still runs is joined. It leaves the queue only
    // after its cache write, so a page that is not found here is already in
    // the cache if it ran.
    if (!_recognition._has(keys.layout)) {
      try {
        var available = false;
        final record = await _withRead((original, owned) async {
          available = true;
          if (!live() || !owned()) return null;
          return readLayoutCache(original, book.originalDigest, keys.layout);
        });
        if (!available || !live()) return null;
        if (record != null) {
          try {
            final geometry = await _hop(pageGeometryFromLayout, record);
            return live() ? geometry : null;
          } on FormatException {
            // A saved record that does not decode is laid out again.
          }
        }
      } on Exception {
        return null;
      }
      if (!live() || _fatal) return null;
    }
    final lease = _lease;
    if (lease == null) return null;
    _holdWorker();
    final wait = _recognition._wait<PageGeometry>(
      keys.layout,
      keys.text,
      () => _layoutPage(book, page, keys, lease, _hop),
      layout: true,
      background: background,
    );
    if (background) {
      _backgroundWaits.add(wait);
    } else {
      _waits.add(wait);
      _recognizing.value = true;
    }
    try {
      final geometry = await wait.result.future;
      return live() ? geometry : null;
    } on PlatformException catch (error) {
      if (error.code == 'recognition-fatal') _fatal = true;
      return null;
    } on Exception {
      return null;
    } finally {
      _backgroundWaits.remove(wait);
      if (_waits.remove(wait) && !_closed) {
        _recognizing.value = _waits.isNotEmpty;
      }
    }
  }

  void _holdWorker() {
    if (_holding) return;
    _holding = true;
    _recognition._hold();
  }

  Future<T?> _withRead<T>(
    Future<T?> Function(VerifiedFile original, bool Function() owned) action,
  ) {
    final lease = _lease;
    if (_closed || lease == null) return Future.value(null);
    var read = _read;
    if (read == null || !read.accepting) {
      read = _OwnedTextRead(lease);
      _read = read;
    }
    return read.use(action);
  }

  _Read _select(int page, _Recognized recognized) {
    if (recognized.text.status == PdfTextStatus.candidate) {
      // Only verified disk-backed results may leave the in-memory selection.
      // Failed publications keep their sole successful copy until close.
      _selected[page] = recognized;
      final cachedPages = _selected.entries
          .where((entry) => entry.value.saved)
          .map((entry) => entry.key)
          .toList();
      if (cachedPages.length > 16) _selected.remove(cachedPages.first);
    }
    return (text: recognized.text, words: recognized.words);
  }

  /// Stops this reader's waits and closes it. It does not wait for work
  /// that runs: that work finishes and is saved in the background.
  @override
  Future<void> close() async {
    cancel();
    _closed = true;
    await _read?.done;
    try {
      await _recognition._release(held: _holding);
    } finally {
      _holding = false;
      _selected.clear();
      _recognizing.dispose();
    }
  }

  void checkInvariants() {
    _read?.checkInvariants();
    if (_selected.values.where((value) => value.saved).length > 16 ||
        _selected.values.any(
          (value) => value.text.status != PdfTextStatus.candidate,
        ) ||
        _closed &&
            (_recognizing.value ||
                _waits.isNotEmpty ||
                _backgroundWaits.isNotEmpty ||
                _holding) ||
        !_closed && _recognizing.value != _waits.isNotEmpty) {
      throw StateError(
        'Recognition must show waiting exactly while this reader waits, keep sixteen disk-backed selected pages, and keep unsaved selections until close.',
      );
    }
  }
}

/// Runs the layout pass on source [page] of [book] and saves its layout
/// record in the cache under the layout key of [keys]. A failure saves
/// nothing. The render starts before the first await, so the book stays
/// open until the page is drawn. After that it needs only the download:
/// [lease] reads the original for the cache write alone.
Future<PageGeometry> _layoutPage(
  PdfBook book,
  int page,
  ({String text, String layout}) keys,
  PdfTextLease lease,
  IsolateHop hop,
) async {
  final raster = await book.render(page, 1600);
  final record = await EnglishRecognition.instance._layout(keys.text, raster);
  // The record is decoded while it is saved. The work ends after the save,
  // so a page that left the queue has its record on disk.
  final saving = () async {
    try {
      await lease((original, owned) async {
        await writeLayoutCache(
          original,
          book.originalDigest,
          keys.layout,
          record,
          owned,
        );
        return _canceled; // The lease result is unused.
      });
    } on Exception {
      // A record that is not saved is laid out again on a later visit.
    }
  }();
  try {
    return await hop(pageGeometryFromLayout, record);
  } finally {
    await saving;
  }
}

/// Recognizes source [page] of [book] and saves the recognition output in
/// the cache under [key]. The output is saved whether or not it holds usable
/// text, so a later visit to a page without text does not run recognition
/// again. A failure saves nothing. It reuses the image of the page's layout
/// pass when the engine still keeps it. Otherwise the render starts before
/// the first await, so the book stays open until the page is drawn. After
/// that it needs only the download: [lease] reads the original for the
/// cache write alone, so a running page never holds the download while the
/// native worker runs.
Future<_Recognized> _recognizePage(
  PdfBook book,
  int page,
  String key,
  PdfTextLease lease,
  IsolateHop hop,
) async {
  final output = await EnglishRecognition.instance._recognize(
    key,
    () => book.render(page, 1600),
  );
  final result = await hop(decodeRecognizedPage, output);
  var saved = false;
  try {
    await lease((original, owned) async {
      await writeOcrCache(original, book.originalDigest, key, output, owned);
      saved = owned();
      return result.text;
    });
    if (!saved) return (text: _gone, words: RecognizedWords.none, saved: false);
  } on Exception {
    // The text still shows. It is recognized again after the book closes.
    return (text: result.text, words: result.words, saved: false);
  }
  return (text: result.text, words: result.words, saved: true);
}

// One acquisition serves all admitted text users. The download read remains
// owned until the last user finishes; revocation still comes from downloads.
// Invariants: users are nonnegative; a drained read admits no further users.
class _OwnedTextRead {
  _OwnedTextRead(this._lease);
  final PdfTextLease _lease;
  final _ready = Completer<({VerifiedFile original, bool Function() owned})?>();
  final _drained = Completer<void>();
  Future<void>? _done;
  int _users = 0;
  bool get accepting => !_drained.isCompleted;
  Future<void>? get done => _done;

  Future<T?> use<T>(
    Future<T?> Function(VerifiedFile original, bool Function() owned) action,
  ) async {
    assert(accepting);
    _users++;
    _done ??= _acquire();
    try {
      final access = await _ready.future;
      if (access == null) return null;
      return await action(access.original, access.owned);
    } finally {
      _users--;
      if (_users == 0) {
        _drained.complete();
        await _done;
      }
    }
  }

  Future<void> _acquire() async {
    try {
      await _lease((original, owned) async {
        _ready.complete((original: original, owned: owned));
        await _drained.future;
        return _canceled; // The lease result is unused; each user owns its result.
      });
      if (!_ready.isCompleted) _ready.complete(null);
    } catch (error, stack) {
      if (_ready.isCompleted) rethrow;
      _ready.completeError(error, stack);
    }
  }

  void checkInvariants() {
    if (_users < 0 || accepting != (_users > 0)) {
      throw StateError(
        'An owned text read admits users until its last user leaves.',
      );
    }
  }
}

final _canceled = _failure('Recognition stopped.');
final _gone = _failure('The download of this book is no longer available.');
final _recognitionFailure = _failure('Text recognition failed on this page.');
final _fatalFallback = _failure(
  'Text recognition stopped working. Restart Bookfin to recognize pages.',
);

PdfText _failure(String reason) => PdfText(
  source: '',
  text: '',
  sourceOffsets: const [],
  status: PdfTextStatus.failed,
  reason: reason,
);

/// The recognized text of a page whose content does not reflow: [status]
/// is [PdfTextStatus.absent] or [PdfTextStatus.unreliable].
PdfText _noReflow(PdfTextStatus status) =>
    PdfText(source: '', text: '', sourceOffsets: const [], status: status);

/// The reading text of a recognized page, and the words that recognition
/// found on it.
typedef RecognizedPage = ({PdfText text, RecognizedWords words});

/// The page text that the recognition output [hocr] holds, and each of its
/// words with its range of that text and its box. It runs in a hop, so it
/// takes and returns only data that crosses to another isolate.
///
/// The source joins the words of each recognized line with spaces and the
/// lines with line breaks. The reflowed text replaces each line break with a
/// space, so each reflowed character records the source character at the
/// same index. Word boxes are in page units of the page's own box; without
/// that box, they are NaN. A page that is not a candidate has no words.
/// Throws a [FormatException] when [hocr] is not well-formed recognition
/// output.
RecognizedPage decodeRecognizedPage(String hocr) {
  if (hocr.length > 8000000) {
    throw const FormatException('Recognition output is too large.');
  }
  final document = XmlDocument.parse(hocr);
  final lines = document.descendants
      .whereType<XmlElement>()
      .where(_textLine)
      .toList();
  final source = StringBuffer();
  final boxes = <List<int>>[];
  var shortLines = 0;
  final page = document.descendants.whereType<XmlElement>().where(
    (element) => (element.getAttribute('class') ?? '')
        .split(RegExp(r'\s+'))
        .contains('ocr_page'),
  );
  final pageBox = page.isEmpty ? null : _bbox(page.first);
  final pageWidth = pageBox == null || pageBox[2] <= pageBox[0]
      ? double.nan
      : (pageBox[2] - pageBox[0]).toDouble();
  final wordRanges = <int>[];
  final wordBoxes = <double>[];
  final wordLines = <int>[];
  for (final (lineIndex, line) in lines.indexed) {
    if (line.ancestors.whereType<XmlElement>().any(_textLine)) {
      throw const FormatException('Nested recognized text lines.');
    }
    final box = _bbox(line);
    if (box == null) {
      throw const FormatException('Missing recognized source-page geometry.');
    }
    if (box[2] <= box[0] || box[3] <= box[1]) {
      throw const FormatException('Invalid recognized source-page geometry.');
    }
    boxes.add(box);
    final elements = line.descendants
        .whereType<XmlElement>()
        .where(_word)
        .toList();
    if (elements.any(
      (element) => element.ancestors.whereType<XmlElement>().any(_word),
    )) {
      throw const FormatException('Nested recognized words.');
    }
    if (source.isNotEmpty) source.write('\n');
    var words = 0;
    for (final element in elements) {
      final word = element.innerText.trim();
      if (word.isEmpty) continue;
      if (words > 0) source.write(' ');
      words++;
      wordRanges.add(source.length);
      source.write(word);
      wordRanges.add(source.length);
      final wordBox = pageBox == null ? null : _bbox(element);
      for (var side = 0; side < 4; side++) {
        wordBoxes.add(
          wordBox == null
              ? double.nan
              : (wordBox[side] - pageBox![side % 2]) / pageWidth,
        );
      }
      wordLines.add(lineIndex);
    }
    if (words <= 2) shortLines++;
  }
  final raw = source.toString();
  if (raw.trim().isEmpty) {
    return (text: _noReflow(PdfTextStatus.absent), words: RecognizedWords.none);
  }
  if (raw.length > 2000000 ||
      raw.contains('\uFFFD') ||
      raw.contains('\u0000')) {
    return (
      text: _noReflow(PdfTextStatus.unreliable),
      words: RecognizedWords.none,
    );
  }
  var parallelRows = 0;
  final rows = <int, ({int minimumRight, int maximumLeft})>{};
  for (final box in boxes) {
    for (var bottom = box[3] - 3; bottom <= box[3] + 3; bottom++) {
      final previous = rows[bottom];
      if (previous != null &&
          (previous.minimumRight < box[0] || box[2] < previous.maximumLeft)) {
        parallelRows++;
        break;
      }
    }
    final previous = rows[box[3]];
    rows[box[3]] = (
      minimumRight: previous != null && previous.minimumRight < box[2]
          ? previous.minimumRight
          : box[2],
      maximumLeft: previous != null && previous.maximumLeft > box[0]
          ? previous.maximumLeft
          : box[0],
    );
  }
  final unreliable =
      parallelRows >= 3 || boxes.length >= 4 && shortLines / boxes.length >= .8;
  final text = StringBuffer();
  final offsets = <int>[];
  for (var index = 0; index < raw.length; index++) {
    text.write(raw[index] == '\n' ? ' ' : raw[index]);
    offsets.add(index);
  }
  return (
    text: PdfText(
      source: raw,
      text: text.toString(),
      sourceOffsets: offsets,
      recognition: BundledEnglishText.version,
      status: unreliable ? PdfTextStatus.unreliable : PdfTextStatus.candidate,
      digest: unreliable ? null : pdfTextDigest(raw),
    ),
    words: unreliable
        ? RecognizedWords.none
        : RecognizedWords(
            ranges: Int32List.fromList(wordRanges),
            boxes: Float32List.fromList(wordBoxes),
            lines: Int32List.fromList(wordLines),
          ),
  );
}

/// The `bbox` of the hOCR [element]'s title: left, top, right and bottom in
/// pixels, or null when the title has none.
List<int>? _bbox(XmlElement element) {
  final match = RegExp(r'(?:^|;)\s*bbox (\d+) (\d+) (\d+) (\d+)(?:;|$)')
      .firstMatch(element.getAttribute('title') ?? '');
  if (match == null) return null;
  return [
    for (var index = 1; index <= 4; index++) int.parse(match.group(index)!),
  ];
}

bool _textLine(XmlElement element) => (element.getAttribute('class') ?? '')
    .split(RegExp(r'\s+'))
    .any(
      (name) => const {
        'ocr_line',
        'ocr_header',
        'ocr_textfloat',
        'ocr_caption',
      }.contains(name),
    );

bool _word(XmlElement element) => (element.getAttribute('class') ?? '')
    .split(RegExp(r'\s+'))
    .contains('ocrx_word');
