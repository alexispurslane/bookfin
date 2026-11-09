import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart';

import '../downloads/downloads.dart';
import '../foundation/hop.dart';
import 'ocr_storage.dart';
import 'pdf.dart';

/// The text of a recognized page, and whether its cache file holds it.
typedef _Recognized = ({PdfText text, bool saved});

/// The one owner of English page recognition while Bookfin runs. Android
/// has one native recognition worker, so the pages of every open PDF wait
/// in this one queue. No reader and no widget owns a page that runs.
///
/// A page that starts always finishes and saves its text in the cache,
/// whether or not a reader still waits for it. A reader that turns the
/// page, cancels, closes the book or leaves the app only stops waiting. A
/// page that has not started yet leaves the queue when its last reader
/// stops waiting. The native worker closes when no reader holds it and no
/// page waits or runs.
///
/// Invariants: at most one page runs, and it is not among the waiting
/// pages; every waiting page has a reader that waits for it; [_pages] holds
/// exactly the waiting pages and the running page; no page starts while
/// the native worker closes.
class EnglishRecognition {
  EnglishRecognition._();
  static final instance = EnglishRecognition._();
  static const _channel = MethodChannel('bookfin/ocr');
  final Map<String, _Page> _pages = {};
  final List<_Page> _waiting = [];
  _Page? _running;
  int _holders = 0;
  Future<void>? _closing;

  /// Whether the page saved under [key] waits or runs.
  bool _has(String key) => _pages.containsKey(key);

  /// Waits for the page saved under [key]. If that page does not wait or
  /// run, [recognize] runs it after the pages before it. [recognize] must
  /// claim what it needs before its first await, because the reader can
  /// stop waiting at any later moment.
  _Wait _wait(String key, Future<_Recognized> Function() recognize) {
    assert(_holders > 0, 'A reader that waits holds the native worker.');
    final page = _pages.putIfAbsent(key, () {
      final added = _Page(key, recognize);
      _waiting.add(added);
      return added;
    });
    final wait = _Wait(this, page);
    page.waits.add(wait);
    _start();
    return wait;
  }

  void _leave(_Wait wait) {
    final page = wait.page;
    if (!page.waits.remove(wait)) return;
    wait.result.complete(null);
    if (page.waits.isEmpty && !identical(page, _running)) {
      // A reader that waits holds the worker, so its close follows later.
      _waiting.remove(page);
      _pages.remove(page.key);
    }
  }

  void _start() {
    if (_running != null || _closing != null || _waiting.isEmpty) return;
    final page = _running = _waiting.removeAt(0);
    unawaited(_finish(page, page.recognize()));
  }

  Future<void> _finish(_Page page, Future<_Recognized> running) async {
    try {
      final recognized = await running;
      for (final wait in page.waits) {
        wait.result.complete(recognized);
      }
    } catch (error, stack) {
      // A failure that no reader waits for has nobody to tell. The page is
      // recognized again when a reader next opens it.
      for (final wait in page.waits) {
        wait.result.completeError(error, stack);
      }
    } finally {
      page.waits.clear();
      _pages.remove(page.key);
      _running = null;
      _start();
      // A close failure that no closing book waits for is not reported. The
      // next page opens a new worker, and native recognition refuses an
      // unsafe one.
      unawaited(_closeIfIdle().catchError((Object _) {}));
    }
  }

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
    if (_holders < 0 ||
        running != null && _waiting.contains(running) ||
        _waiting.any((page) => page.waits.isEmpty) ||
        _pages.length != _waiting.length + (running == null ? 0 : 1) ||
        _waiting.any((page) => !identical(_pages[page.key], page)) ||
        running != null && !identical(_pages[running.key], running) ||
        _closing != null && running != null) {
      throw StateError(
        'Recognition must run at most one page, keep only waited-for pages waiting, and never run a page while the native worker closes.',
      );
    }
  }
}

class _Page {
  _Page(this.key, this.recognize);
  final String key;
  final Future<_Recognized> Function() recognize;
  final Set<_Wait> waits = {};
}

/// One reader's wait for one page. Its result is null when the reader
/// stopped waiting.
class _Wait {
  _Wait(this._owner, this.page);
  final EnglishRecognition _owner;
  final _Page page;
  final result = Completer<_Recognized?>();
  void leave() => _owner._leave(this);
}

class BundledEnglishText implements PdfTextSupply {
  /// Recognizes English text on scanned pages. Each recognized page, new or
  /// cached, is decoded through `hop`. Pages run in
  /// [EnglishRecognition.instance], so a page that started finishes and is
  /// saved after this reader stops waiting or closes.
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
  final Set<_Wait> _waits = {};
  final Map<int, ({PdfText text, bool saved})> _selected = {};
  _OwnedTextRead? _read;
  final _recognizing = ValueNotifier(false);
  @override
  ValueListenable<bool> get recognizing => _recognizing;
  @override
  void bind(PdfTextLease lease) => _lease = lease;

  /// Stops every wait of this reader. A page that started still finishes
  /// and is saved; a page that did not start leaves the queue.
  @override
  void cancel() {
    _generation++;
    final waits = _waits.toList();
    _waits.clear();
    for (final wait in waits) {
      wait.leave();
    }
    if (!_closed) _recognizing.value = false;
  }

  @override
  Future<PdfText> text(PdfBook book, int page, PdfText extracted) async {
    if (extracted.status == PdfTextStatus.candidate || _closed) {
      return Future.value(extracted);
    }
    final generation = _generation;
    final key = sha256
        .convert(utf8.encode('$version/${book.originalDigest}/$page'))
        .toString();
    Future<PdfText?> reuse(VerifiedFile original, bool Function() owned) async {
      bool live() => !_closed && generation == _generation && owned();
      if (!live()) return _canceled;
      // Cache access also makes sure that the download still holds this
      // book before this reader reuses its selected text.
      final cached = await readOcrCache(original, book.originalDigest, key);
      if (!live()) return _canceled;
      final selected = _selected[page];
      if (selected != null) return selected.text;
      if (cached == null) return null;
      final PdfText saved;
      try {
        saved = await _hop(decodeRecognizedPage, cached);
      } on Exception {
        return null; // A cached page that does not decode is recognized again.
      }
      return live() ? _select(page, saved) : _canceled;
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
        if (!available) return _canceled;
        if (reused != null) return reused;
      } on Exception {
        return _recognitionFailure;
      }
      if (_closed || generation != _generation) return _canceled;
      if (_fatal) return _fatalFallback;
    }
    final lease = _lease;
    if (lease == null) {
      return _fallback('Text recognition needs the downloaded book.');
    }
    if (!_holding) {
      _holding = true;
      _recognition._hold();
    }
    final wait = _recognition._wait(
      key,
      () => _recognizePage(book, page, key, lease, _hop),
    );
    _waits.add(wait);
    _recognizing.value = true;
    try {
      final recognized = await wait.result.future;
      if (recognized == null || _closed || generation != _generation) {
        return _canceled;
      }
      return _select(page, recognized.text, saved: recognized.saved);
    } on PlatformException catch (error) {
      if (error.code == 'recognition-fatal') {
        _fatal = true;
        return _fatalFallback;
      }
      return _recognitionFailure;
    } on Exception {
      return _recognitionFailure;
    } finally {
      if (_waits.remove(wait) && !_closed) {
        _recognizing.value = _waits.isNotEmpty;
      }
    }
  }

  Future<PdfText?> _withRead(
    Future<PdfText?> Function(VerifiedFile original, bool Function() owned)
    action,
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

  PdfText _select(int page, PdfText text, {bool saved = true}) {
    if (text.status == PdfTextStatus.candidate) {
      // Only verified disk-backed results may leave the in-memory selection.
      // Failed publications keep their sole successful copy until close.
      _selected[page] = (text: text, saved: saved);
      final cachedPages = _selected.entries
          .where((entry) => entry.value.saved)
          .map((entry) => entry.key)
          .toList();
      if (cachedPages.length > 16) _selected.remove(cachedPages.first);
    }
    return text;
  }

  /// Stops this reader's waits and closes it. It does not wait for a page
  /// that runs: that page finishes and is saved in the background.
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
        _closed && (_recognizing.value || _waits.isNotEmpty || _holding) ||
        !_closed && _recognizing.value != _waits.isNotEmpty) {
      throw StateError(
        'Recognition must show waiting exactly while this reader waits, keep sixteen disk-backed selected pages, and keep unsaved selections until close.',
      );
    }
  }
}

/// Recognizes source [page] of [book] and saves its text in the cache
/// under [key]. The render starts before the first await, so the book
/// stays open until the page is drawn. After that it needs only the
/// download: [lease] reads the original for the cache write alone, so a
/// running page never holds the download while the native worker runs.
Future<_Recognized> _recognizePage(
  PdfBook book,
  int page,
  String key,
  PdfTextLease lease,
  IsolateHop hop,
) async {
  final raster = await book.render(page, 1600);
  final hocr = await EnglishRecognition._channel.invokeMethod<String>(
    'recognize',
    {'width': raster.width, 'height': raster.height, 'bgra': raster.bgra},
  );
  final result = await hop(decodeRecognizedPage, hocr ?? '');
  if (result.status != PdfTextStatus.candidate) {
    return (text: result, saved: false);
  }
  var saved = false;
  try {
    await lease((original, owned) async {
      await writeOcrCache(original, book.originalDigest, key, hocr!, owned);
      saved = owned();
      return result;
    });
    if (!saved) return (text: _gone, saved: false);
  } on Exception {
    // The text still shows. It is recognized again after the book closes.
    return (text: result, saved: false);
  }
  return (text: result, saved: true);
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

  Future<PdfText?> use(
    Future<PdfText?> Function(VerifiedFile original, bool Function() owned)
    action,
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

const _canceled = PdfText(
  source: '',
  text: '',
  sourceOffsets: [],
  status: PdfTextStatus.absent,
  reason: 'Recognition stopped.',
);

final _gone = _fallback('The download of this book is no longer available.');
final _recognitionFailure = _fallback('Text recognition failed on this page.');
final _fatalFallback = _fallback(
  'Text recognition stopped working. Restart Bookfin to recognize pages.',
);

PdfText _fallback(String reason) => PdfText(
  source: '',
  text: '',
  sourceOffsets: const [],
  status: PdfTextStatus.absent,
  reason: reason,
);

/// The page text that the recognition output [hocr] holds. It runs in a hop,
/// so it takes and returns only data that crosses to another isolate.
///
/// The source joins the words of each recognized line with spaces and the
/// lines with line breaks. The reflowed text replaces each line break with a
/// space, so each reflowed character records the source character at the
/// same index. Throws a [FormatException] when [hocr] is not well-formed
/// recognition output.
PdfText decodeRecognizedPage(String hocr) {
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
  for (final line in lines) {
    if (line.ancestors.whereType<XmlElement>().any(_textLine)) {
      throw const FormatException('Nested recognized text lines.');
    }
    final title = line.getAttribute('title') ?? '';
    final match = RegExp(r'(?:^|;)\s*bbox (\d+) (\d+) (\d+) (\d+)(?:;|$)')
        .firstMatch(title);
    if (match == null) {
      throw const FormatException('Missing recognized source-page geometry.');
    }
    final box = [
      for (var index = 1; index <= 4; index++) int.parse(match.group(index)!),
    ];
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
    final words = elements
        .map((element) => element.innerText.trim())
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.length <= 2) shortLines++;
    if (source.isNotEmpty) source.write('\n');
    source.write(words.join(' '));
  }
  final raw = source.toString();
  if (raw.trim().isEmpty) {
    return _fallback('No text was found on this page.');
  }
  if (raw.length > 2000000 ||
      raw.contains('\uFFFD') ||
      raw.contains('\u0000')) {
    return _fallback('The recognized text of this page cannot be read.');
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
  return PdfText(
    source: raw,
    text: text.toString(),
    sourceOffsets: offsets,
    recognition: BundledEnglishText.version,
    status: unreliable ? PdfTextStatus.unreliable : PdfTextStatus.candidate,
    digest: unreliable ? null : pdfTextDigest(raw),
    reason: unreliable
        ? 'The text of this page cannot be put in reading order.'
        : null,
  );
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
