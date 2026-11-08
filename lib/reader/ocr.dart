import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart';

import 'ocr_storage.dart';
import 'pdf.dart';

class BundledEnglishText implements PdfTextSupply {
  static const version =
      'bookfin-ocr-2/tesseract4android-4.9.0/tesseract-5.5.1/leptonica-1.85.0/tessdata_fast-4.1.0-eng-7d4322bd2a7749724879683fc3912cb542f19906c83bcc1a52132556427170b2';
  static const _channel = MethodChannel('bookfin/ocr');
  PdfTextLease? _lease;
  int _generation = 0;
  bool _closed = false;
  bool _fatal = false;
  Future<void> _draining = Future.value();
  final Map<({int page, int generation}), Future<PdfText>> _pending = {};
  final Set<int> _requested = {};
  final Map<int, ({PdfText text, bool saved})> _selected = {};
  _OwnedTextRead? _read;
  final _recognizing = ValueNotifier(false);
  @override
  ValueListenable<bool> get recognizing => _recognizing;
  @override
  bool get canRetry => !_closed && !_fatal;

  @override
  void bind(PdfTextLease lease) => _lease = lease;
  @override
  void retry(int page) => _requested.add(page);
  @override
  void cancel() {
    _generation++;
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
    Future<PdfText?> reuse(Uri original, bool Function() owned) async {
      bool live() => !_closed && generation == _generation && owned();
      if (!live()) return _canceled;
      // Cache access also verifies original bytes before reusing selected text.
      final cached = await readOcrCache(original, book.originalDigest, key);
      if (!live()) return _canceled;
      final selected = _selected[page];
      if (selected != null) return selected.text;
      final saved = _cachedPage(cached);
      return saved == null ? null : _select(page, saved);
    }

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
    final request = (page: page, generation: _generation);
    if (_pending.containsKey(request)) return _pending[request]!;
    if (_pending.length >= 2) {
      return Future.value(
        _fallback('Recognition is busy. Retry this source page.'),
      );
    }
    final previous = _draining;
    final operation = () async {
      await previous;
      if (_fatal) return _fatalFallback;
      bool requestLive() => !_closed && generation == _generation;
      if (!requestLive()) return _canceled;
      final lease = _lease;
      if (lease == null) {
        return _fallback(
          'English scan recognition requires an owned local download.',
        );
      }
      try {
        return await _withRead((original, owned) async {
              bool live() => requestLive() && owned();
              if (!live()) return _canceled;
              final reused = await reuse(original, owned);
              if (reused != null) return reused;
              if (extracted.status == PdfTextStatus.unreliable &&
                  !_requested.contains(page)) {
                return extracted;
              }
              _recognizing.value = true;
              final raster = await book.render(page, 1600);
              if (!live()) return _canceled;
              final hocr = await _channel.invokeMethod<String>('recognize', {
                'width': raster.width,
                'height': raster.height,
                'bgra': raster.bgra,
              });
              if (!live()) return _canceled;
              final result = decodeRecognizedPage(hocr ?? '');
              if (result.status == PdfTextStatus.candidate) {
                try {
                  await writeOcrCache(
                    original,
                    book.originalDigest,
                    key,
                    hocr!,
                    live,
                  );
                } on Exception {
                  if (!live()) return _canceled;
                  return _select(
                    page,
                    PdfText(
                      source: result.source,
                      text: result.text,
                      sourceOffsets: result.sourceOffsets,
                      status: result.status,
                      recognition: result.recognition,
                      digest: result.digest,
                      reason: 'English text is available, but could not be cached. Free storage to save recognition.',
                    ),
                    saved: false,
                  );
                }
              }
              return live() ? _select(page, result) : _canceled;
            }) ??
            _fallback(
              'The download is no longer available. The original page remains open.',
            );
      } on PlatformException catch (error) {
        if (error.code == 'recognition-fatal') {
          _fatal = true;
          return _fatalFallback;
        }
        return _recognitionFailure;
      } on Exception {
        return _recognitionFailure;
      }
    }();
    _pending[request] = operation;
    _draining = operation.then<void>((_) {
      if (!_closed && generation == _generation) _recognizing.value = false;
      if (identical(_pending[request], operation)) _pending.remove(request);
    });
    return operation;
  }

  Future<PdfText?> _withRead(
    Future<PdfText?> Function(Uri original, bool Function() owned) action,
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

  @override
  Future<void> close() async {
    cancel();
    _closed = true;
    await _draining;
    await _read?.done;
    try {
      await _channel.invokeMethod<void>('close');
    } finally {
      _selected.clear();
      _recognizing.dispose();
    }
  }

  void checkInvariants() {
    _read?.checkInvariants();
    if (_pending.length > 2 ||
        _selected.values.where((value) => value.saved).length > 16 ||
        _selected.values.any(
          (value) => value.text.status != PdfTextStatus.candidate,
        ) ||
        _closed && _recognizing.value) {
      throw StateError(
        'Recognition must have at most one active page, one waiting page, and sixteen disk-backed selected pages; unsaved selections remain until close.',
      );
    }
  }
}

// One acquisition serves all admitted text users. The download read remains
// owned until the last user finishes; revocation still comes from downloads.
// Invariants: users are nonnegative; a drained read admits no further users.
class _OwnedTextRead {
  _OwnedTextRead(this._lease);
  final PdfTextLease _lease;
  final _ready = Completer<({Uri original, bool Function() owned})?>();
  final _drained = Completer<void>();
  Future<void>? _done;
  int _users = 0;
  bool get accepting => !_drained.isCompleted;
  Future<void>? get done => _done;

  Future<PdfText?> use(
    Future<PdfText?> Function(Uri original, bool Function() owned) action,
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
  reason: 'Recognition canceled. The original page is available.',
);

final _recognitionFailure = _fallback(
  'English recognition failed. Retry or read the original page.',
);
final _fatalFallback = _fallback(
  'English recognition cannot continue safely. Restart Bookfin. The original page remains available.',
);

PdfText? _cachedPage(String? hocr) {
  if (hocr == null) return null;
  try {
    return decodeRecognizedPage(hocr);
  } on Exception {
    return null;
  }
}

PdfText _fallback(String reason) => PdfText(
  source: '',
  text: '',
  sourceOffsets: const [],
  status: PdfTextStatus.absent,
  reason: reason,
);

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
    return _fallback('No English text was recognized. Read the original page.');
  }
  if (raw.length > 2000000 ||
      raw.contains('\uFFFD') ||
      raw.contains('\u0000')) {
    return _fallback('Recognized text is unreliable. Read the original page.');
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
        ? 'Recognized text order is unreliable. Read the original page.'
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
