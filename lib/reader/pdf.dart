import 'dart:typed_data';
import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'dart:ui' show RootIsolateToken;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show ValueListenable, compute;
import 'package:pdfrx_engine/pdfrx_engine.dart' as native;
import 'package:pdfrx/pdfrx.dart' show pdfrxFlutterInitialize;

import '../downloads/downloads.dart';
import '../foundation/hop.dart';
import 'book_survey.dart';
import 'column_layout.dart';
import 'document.dart';
import 'page_analysis.dart';
import 'page_geometry.dart';
import 'pdf_outline.dart';
import 'running_lines.dart';
import 'text_outline.dart';
import 'word_bands.dart';

/// How the reader shows a PDF page. The reader session owns the choice for
/// this run of the app, independently of the book and its saved records.
enum PdfPageView { original, pageWords, text }

/// What the text of a source page offers reflow and search. The first three
/// describe the page's own content. Only [failed] describes the reader.
enum PdfTextStatus {
  /// The page's text, in reading order. Reflow shows it, search finds words
  /// in it, and a place inside the page names it by its digest.
  candidate,

  /// The page holds no text, such as a picture or an empty page.
  absent,

  /// The page holds text that cannot be put in reading order, such as a
  /// cover of a few short lines, a contents page of titles beside page
  /// numbers, a diagram or a table.
  unreliable,

  /// The reader could not get the page's text, for a reason that the person
  /// can act on, such as a recognition failure or a removed download.
  /// [PdfText.reason] says what happened.
  failed,
}

class PdfText {
  const PdfText({
    required this.source,
    required this.text,
    required this.sourceOffsets,
    required this.status,
    this.reason,
    this.recognition,
    this.digest,
  }) : assert(
         status != PdfTextStatus.candidate || digest != null,
         'A candidate page text names its digest.',
       ),
       assert(
         (status == PdfTextStatus.failed) == (reason != null),
         'Exactly a failed page text says why it failed.',
       );
  final String source;
  final String text;
  final List<int> sourceOffsets;
  final PdfTextStatus status;

  /// Why the reader could not get the text, in one sentence for the person.
  /// A [PdfTextStatus.failed] text has one, and no other text has one.
  final String? reason;
  final String? recognition;

  /// The [pdfTextDigest] of [source]. An address inside the page names its
  /// text by it, so every candidate text has one. Whoever builds the text
  /// computes it, so that [PdfBook.addressFor] answers without hashing.
  final String? digest;
}

/// The digest that names the page text [source] in an address: the SHA-256
/// of its UTF-8 bytes, as lowercase hex.
String pdfTextDigest(String source) =>
    sha256.convert(utf8.encode(source)).toString();

/// The longest extracted page text, in UTF-16 code units, that a source
/// page offers for reflow.
const _pageTextLimit = 2000000;

/// Where the words of a text layer page are, and each word's range of the
/// page's `PdfText.source`.
typedef TextLayerWords = ({PageGeometry geometry, TextAttachment attachment});

/// What the text layer of one source page offers the reader: its text, and
/// its [TextLayerWords] when the text is a candidate and its character boxes
/// are usable.
typedef PreparedPdfPage = ({PdfText text, TextLayerWords? words});

/// The page text that one source page offers the reader, and its words.
/// [page] holds the extracted text, its character boxes (left, top, right
/// and bottom in PDF points, with y up, for each UTF-16 code unit of the
/// text), and the page's width and height in PDF points. It runs in a hop,
/// so it takes only data that crosses to another isolate as blocks.
///
/// The reflowed text joins each run of whitespace into one space and drops
/// whitespace at both ends. Each reflowed character records the source
/// character that it came from, and a joining space records the first
/// whitespace character of its run.
PreparedPdfPage preparePdfPage(
  ({String source, Float64List boxes, double width, double height}) page,
) {
  final source = page.source;
  final output = StringBuffer();
  final offsets = <int>[];
  final words = <int>[];
  var start = 0;
  for (var index = 0; index <= source.length; index++) {
    if (index < source.length && !_whitespace(source.codeUnitAt(index))) {
      continue;
    }
    if (start < index) {
      if (offsets.isNotEmpty) {
        output.write(' ');
        offsets.add(offsets.last + 1);
      }
      output.write(source.substring(start, index));
      var word = start;
      for (var offset = start; offset < index; offset++) {
        offsets.add(offset);
        // pdfium joins the two halves of a word that a hyphen splits at a
        // line end, and puts U+0002 in place of the hyphen. Each half is a
        // printed word of its own line.
        if (source.codeUnitAt(offset) == 0x02 && offset + 1 < index) {
          words.addAll([word, offset + 1]);
          word = offset + 1;
        }
      }
      words.addAll([word, index]);
    }
    start = index + 1;
  }
  final status = offsets.isEmpty
      ? PdfTextStatus.absent
      : _outOfOrder(source, page.boxes)
      ? PdfTextStatus.unreliable
      : PdfTextStatus.candidate;
  final text = PdfText(
    source: source,
    text: output.toString(),
    sourceOffsets: offsets,
    status: status,
    digest: status == PdfTextStatus.candidate ? pdfTextDigest(source) : null,
  );
  if (status != PdfTextStatus.candidate) return (text: text, words: null);
  return (
    text: text,
    words: pageGeometryFromCharacters(
      source: source,
      boxes: page.boxes,
      words: Int32List.fromList(words),
      width: page.width,
      height: page.height,
    ),
  );
}

/// Whether [unit] is a UTF-16 code unit that `RegExp(r'\s')` matches.
/// Saved places count reflowed characters, so this set must not change.
bool _whitespace(int unit) =>
    unit >= 0x09 && unit <= 0x0D ||
    unit == 0x20 ||
    unit == 0xA0 ||
    unit == 0x1680 ||
    unit >= 0x2000 && unit <= 0x200A ||
    unit == 0x2028 ||
    unit == 0x2029 ||
    unit == 0x202F ||
    unit == 0x205F ||
    unit == 0x3000 ||
    unit == 0xFEFF;

/// The text of a page for reading, and for each word of a page's geometry,
/// its range of that text, or null when the text is not a candidate or
/// nothing attaches it.
typedef AttachedText = ({PdfText text, TextAttachment? attachment});

/// What the word view needs of one source page. [PdfBook.reflowPage] gives
/// it.
class ReflowPage {
  ReflowPage._(this._entry, this.bodyLineHeight)
    : geometry = _entry.analyzed!.geometry,
      analysis = _entry.analyzed!.analysis;

  final _ReflowEntry _entry;

  /// The page's reflow geometry: its word geometry, with the ink that no
  /// word covers as extra words of their lines, and on a scanned page with
  /// the hyphens and raised marks that its pixels show.
  final PageGeometry geometry;

  /// The facts about the page that need its pixels, for [geometry].
  final PageAnalysis analysis;

  /// The line height that scales the page's words, in page units: the
  /// page's body line height when it has at least 8 prose lines, and
  /// otherwise the book's body line height in this session. Until the book
  /// has one, it is the page's own.
  final double bodyLineHeight;

  /// The page's text for reading, as [PdfBook.text] gives it, and for each
  /// word of [geometry], its range of that text. An extra word names no
  /// text: its range is empty, at the end of the word before it. It
  /// completes when the reading text arrives. On a scanned page that is
  /// after recognition, seconds after the geometry. The first call asks
  /// for the text, and later calls share it. A text that failed, such as a
  /// canceled recognition, or an error, is asked for again by the next
  /// call.
  Future<AttachedText> attachedText() => _entry.attachedText();

  /// The page as the book's running templates read it (see
  /// `RunningTemplates`): its number, [geometry], [analysis], and the text
  /// of its text layer. A scanned page has no text here, even after its
  /// recognition, so its running lines are found from their place and
  /// size alone. The survey reads each page through this, so the Original
  /// view's crop and the word view leave out the same lines.
  Future<AnalyzedSourcePage> templateReading() async {
    final book = _entry.book, page = _entry.page;
    final layer = await book.textLayer(page);
    final attached = layer.status == PdfTextStatus.candidate
        ? await attachedText()
        : null;
    final attachment = attached?.attachment;
    return (
      sourcePage: page,
      geometry: geometry,
      analysis: analysis,
      text: attachment == null
          ? null
          : (source: attached!.text.source, attachment: attachment),
    );
  }

  /// The page's words and regions in lines and screens for [settings], as
  /// [layoutColumn] gives them, through the book's hop. Once the book
  /// profile froze (see [PdfBook.survey]), the column leaves out the
  /// page's running headers, folios and running regions, which the
  /// profile's templates mark as they do for the Original view's crop.
  /// Until then it shows them, and a column asked for after the freeze
  /// differs. It reads [geometry], [analysis], [bodyLineHeight] and the
  /// text of a text layer page, never a scanned page's recognized text, so
  /// the arrival of that text does not change it.
  Future<ReflowColumn> column(ColumnSettings settings) async =>
      _entry.book.hop(layoutColumn, (
        geometry: geometry,
        analysis: await _shownAnalysis(),
        bodyLineHeight: bodyLineHeight,
        settings: settings,
      ));

  /// The column for [settings], as [column] lays it out, and the bands of
  /// its screens, as [planWordColumn] plans them, in one hop.
  Future<WordColumn> wordColumn(WordSettings settings) async =>
      _entry.book.hop(planWordColumn, (
        geometry: geometry,
        analysis: await _shownAnalysis(),
        bodyLineHeight: bodyLineHeight,
        settings: settings,
      ));

  /// The analysis that a column reads: [analysis], with the running lines
  /// and regions marked once the book profile froze.
  Future<PageAnalysis> _shownAnalysis() async {
    final templates = _entry.book.survey.profile?.templates;
    return templates == null
        ? analysis
        : templates.mark(await templateReading());
  }
}

/// One page that [PdfBook] keeps for reflow: its analysis while it runs or
/// when it is done, and its attached text once something asks for it.
class _ReflowEntry {
  _ReflowEntry(this.book, this.page, {required this.background});
  final PdfBook book;
  final int page;

  /// Whether the analysis is a background request, such as the survey's: it
  /// asks for the page's geometry before it draws the page, and its layout
  /// pass waits behind all other recognition work. A request of the reader
  /// that joins it clears it.
  bool background;

  /// Whether the analysis waits for the page's word geometry.
  var _awaitingGeometry = true;

  /// The analysis, which completes with null when the page has no word
  /// geometry.
  late final Future<void> done = _analyze();

  /// The page's word geometry, as [PdfBook.geometry] gives it, and the
  /// analysis, once they are done.
  PageGeometry? source;
  AnalyzedPage? analyzed;

  Future<AttachedText>? _attached;

  /// The attached text, once it arrived.
  AttachedText? arrived;

  Future<void> _analyze() async {
    // The reader's page draws while its geometry is found: on a scanned page
    // the layout pass runs on the recognition worker, beside pdfium. A
    // background page draws only once it has geometry, so a page without
    // any costs no drawing.
    var drawn = background ? null : book.render(page, PdfBook._analysisWidth);
    final PageGeometry? geometry;
    final PdfText layer;
    try {
      geometry = await book.geometry(page, background: background);
      layer = await book.textLayer(page);
    } catch (_) {
      drawn?.ignore();
      rethrow;
    } finally {
      _awaitingGeometry = false;
    }
    if (geometry == null) {
      drawn?.ignore();
      return;
    }
    drawn ??= book.render(page, PdfBook._analysisWidth);
    final raster = await drawn;
    // Only this call holds the raster, so it is freed when the analysis
    // ends. The book keeps only the analysis's small typed lists.
    analyzed = await book.hop(analyzePage, (
      width: raster.width,
      height: raster.height,
      bgra: raster.bgra,
      geometry: geometry,
      scanned: layer.status != PdfTextStatus.candidate,
    ));
    source = geometry;
  }

  Future<AttachedText> attachedText() => _attached ??= _attach();

  Future<AttachedText> _attach() async {
    final AttachedText read;
    try {
      read = await book.attachedText(page, source!);
    } catch (_) {
      _attached = null;
      rethrow;
    }
    // A failed text, such as a canceled recognition, can arrive when it is
    // asked again.
    if (read.text.status == PdfTextStatus.failed) _attached = null;
    final attachment = read.attachment;
    // Mapping one range for each word takes microseconds, far less than a
    // hop to another isolate.
    final attached = (
      text: read.text,
      attachment: attachment == null
          ? null
          : reflowAttachment(attachment, analyzed!.analysis),
    );
    arrived = attached;
    return attached;
  }
}

class PdfRaster {
  const PdfRaster(this.width, this.height, this.bgra);
  final int width;
  final int height;
  final Uint8List bgra;
}

abstract class PdfBook extends ReaderDocument {
  /// [hop] runs the page analysis, and the preparation of a native book's
  /// page texts, in another isolate.
  PdfBook({this.hop = compute});

  /// Runs work in another isolate.
  final IsolateHop hop;

  /// The background survey of the book's pages, for its crops.
  late final survey = BookSurvey(this);

  /// The width in pixels at which the page analysis draws a page. The
  /// layout pass and recognition draw at the same width, so their boxes
  /// match the analysis's pixels.
  static const _analysisWidth = 1600.0;

  /// How many reflow pages the book keeps.
  static const _keptReflowPages = 16;

  /// The reflow pages that the book keeps, the least recently asked first.
  final _reflowPages = <int, _ReflowEntry>{};

  /// The background requests that run, outside [_reflowPages].
  final _backgroundPages = <int, _ReflowEntry>{};

  /// How many requests of the reader run, and a completer that completes
  /// when none does.
  var _readerRequests = 0;
  Completer<void>? _readerIdle;

  /// For each page with at least 8 prose lines that the book analyzed in
  /// this session: its body line height.
  final _bodyLineHeights = <int, double>{};

  /// The word geometry and page analysis of [sourcePage] at once, and its
  /// text attachment after the reading text arrives (see
  /// [ReflowPage.attachedText]). Null when the page has no word geometry
  /// (see [geometry]). The analysis draws the page and runs through [hop];
  /// it reads no text. The book keeps the last 16 pages that it gave, so a
  /// kept page is not drawn or analyzed again.
  ///
  /// A [background] request, such as the survey's, has the lowest priority.
  /// It starts only while no request of the reader runs, its layout pass
  /// waits behind all other recognition work (see [geometry]), and the book
  /// does not keep its page, so it never pushes the reader's pages out. It
  /// joins a page that the book keeps or analyzes. A request of the reader
  /// for a page that a background request analyzes joins it, keeps it, and
  /// moves its layout pass to the front.
  Future<ReflowPage?> reflowPage(
    int sourcePage, {
    bool background = false,
  }) async {
    if (background) return _backgroundPage(sourcePage);
    _readerRequests++;
    try {
      return await _readerPage(sourcePage);
    } finally {
      if (--_readerRequests == 0) {
        _readerIdle?.complete();
        _readerIdle = null;
      }
    }
  }

  Future<ReflowPage?> _readerPage(int sourcePage) async {
    var entry = _reflowPages.remove(sourcePage);
    if (entry == null) {
      entry = _backgroundPages.remove(sourcePage);
      if (entry != null && entry.background) {
        entry.background = false;
        // The reader's own request for the geometry joins the layout pass
        // that waits, and moves it to the front.
        if (entry._awaitingGeometry) geometry(sourcePage).ignore();
      }
    }
    entry ??= _ReflowEntry(this, sourcePage, background: false);
    _reflowPages[sourcePage] = entry;
    if (_reflowPages.length > _keptReflowPages) {
      _reflowPages.remove(_reflowPages.keys.first);
    }
    assert(_reflowPages.length <= _keptReflowPages);
    try {
      await entry.done;
    } catch (_) {
      _forget(entry);
      rethrow;
    }
    return _given(entry);
  }

  Future<ReflowPage?> _backgroundPage(int sourcePage) async {
    while (_readerRequests > 0) {
      await (_readerIdle ??= Completer<void>()).future;
    }
    var entry = _reflowPages[sourcePage] ?? _backgroundPages[sourcePage];
    if (entry == null) {
      entry = _ReflowEntry(this, sourcePage, background: true);
      _backgroundPages[sourcePage] = entry;
    }
    try {
      await entry.done;
    } finally {
      if (identical(_backgroundPages[sourcePage], entry)) {
        _backgroundPages.remove(sourcePage);
      }
    }
    return _given(entry);
  }

  /// The reflow page of [entry], whose analysis is done, or null when the
  /// page has no word geometry.
  ReflowPage? _given(_ReflowEntry entry) {
    final sourcePage = entry.page;
    final analyzed = entry.analyzed;
    if (analyzed == null) {
      _forget(entry);
      return null;
    }
    final own = analyzed.analysis.bodyLineHeight;
    if (analyzed.analysis.proseLineCount >= 8) {
      _bodyLineHeights[sourcePage] = own;
      return ReflowPage._(entry, own);
    }
    return ReflowPage._(
      entry,
      _bodyLineHeights.isEmpty ? own : _median(_bodyLineHeights.values),
    );
  }

  /// Forgets [entry], which failed or found no geometry, so that the next
  /// request for its page tries again.
  void _forget(_ReflowEntry entry) {
    if (identical(_reflowPages[entry.page], entry)) {
      _reflowPages.remove(entry.page);
    }
  }

  /// Throws a [StateError] when an invariant of the reflow pages does not
  /// hold. It runs only on demand, from a test or a debug switch.
  ///
  /// The invariants: the book keeps at most 16 reflow pages. A background
  /// request's page is not among them, and is a background entry. Each analyzed
  /// page's geometry and analysis hold their invariants. Each attached text
  /// that arrived has the digest of its reading text, and its attachment
  /// has a range of that text for each word of the page's reflow geometry.
  /// Each body line height of the book is positive.
  void checkInvariants() {
    void require(bool holds, String rule) {
      if (!holds) throw StateError('PDF reflow pages: $rule.');
    }

    require(
      _reflowPages.length <= _keptReflowPages,
      'the book keeps at most $_keptReflowPages pages',
    );
    for (final MapEntry(key: page, value: entry) in _reflowPages.entries) {
      require(entry.page == page, 'page $page is kept under its number');
      final analyzed = entry.analyzed;
      if (analyzed == null) continue;
      analyzed.geometry.checkInvariants();
      analyzed.analysis.checkInvariants(analyzed.geometry);
      final arrived = entry.arrived;
      if (arrived == null) continue;
      final text = arrived.text;
      require(
        text.status != PdfTextStatus.candidate ||
            text.digest == pdfTextDigest(text.source),
        'the text of page $page has the digest of its source',
      );
      if (arrived.attachment != null) {
        analyzed.geometry.checkInvariants(
          attachment: arrived.attachment,
          source: text.source,
        );
      }
    }
    for (final MapEntry(key: page, value: entry) in _backgroundPages.entries) {
      require(
        entry.page == page && !_reflowPages.containsKey(page),
        'background page $page is kept apart under its number',
      );
    }
    require(
      _bodyLineHeights.values.every((height) => height > 0 && height.isFinite),
      'each body line height is positive',
    );
  }

  /// Recognizes the text of pages whose text layer cannot be read, or null
  /// when this book has no recognition.
  PdfTextSupply? get textSupply => null;
  int get pageCount;

  /// The text layer of [sourcePage]: the text that the page itself holds.
  /// It never runs recognition, so it answers quickly.
  Future<PdfText> textLayer(int sourcePage);

  /// The text of [sourcePage] for reading, which reflow and search use: its
  /// text layer when that is a candidate, and otherwise the text that
  /// [textSupply] gives for the page.
  Future<PdfText> text(int sourcePage) async {
    final layer = await textLayer(sourcePage);
    return textSupply?.text(this, sourcePage, layer) ?? layer;
  }

  /// The word geometry of [sourcePage]: where its printed words are, or null
  /// when the page has none. A page with a usable text layer gets it from its
  /// character boxes, with its text. Another page gets it from
  /// [textSupply]'s layout pass, before its text. This default knows no
  /// character boxes, so it gives a text layer page no geometry.
  ///
  /// A [background] layout pass waits behind all other recognition work (see
  /// [PdfTextSupply.geometry]).
  Future<PageGeometry?> geometry(
    int sourcePage, {
    bool background = false,
  }) async {
    final layer = await textLayer(sourcePage);
    if (layer.status == PdfTextStatus.candidate) return null;
    return textSupply?.geometry(
      this,
      sourcePage,
      layer,
      background: background,
    );
  }

  /// The text of [sourcePage] for reading, as [text] gives it, and for each
  /// word of the page's [geometry], its range of that text. [geometry] is the
  /// page's word geometry as the method `geometry` gave it. The attachment is
  /// null when the text is not a candidate, or when nothing attaches it.
  Future<({PdfText text, TextAttachment? attachment})> attachedText(
    int sourcePage,
    PageGeometry geometry,
  ) async {
    final layer = await textLayer(sourcePage);
    if (layer.status == PdfTextStatus.candidate) {
      return (text: layer, attachment: null);
    }
    return textSupply?.attachedText(this, sourcePage, layer, geometry) ??
        (text: layer, attachment: null);
  }

  Future<PdfRaster> render(int sourcePage, double width);

  /// The pixels [area] of [sourcePage] drawn [pixelsPerPageUnit] pixels
  /// wide, as an image ready to draw. [area] is in pixels of that drawing,
  /// with whole-pixel edges, and at most [WordBands.maxBandSide] pixels on
  /// each side. Its pixels go to the engine from pdfium's own buffer.
  Future<ui.Image> renderPart(
    int sourcePage,
    int pixelsPerPageUnit,
    ui.Rect area,
  );

  PdfAddress addressFor(int sourcePage, PdfText text, int character) {
    if (text.status != PdfTextStatus.candidate ||
        character < 0 ||
        character > text.source.length) {
      throw ArgumentError('Choose a character in available PDF text.');
    }
    return PdfAddress(
      sourcePage,
      character,
      pageCount: pageCount,
      quote: text.source.substring(
        character,
        (character + 160).clamp(0, text.source.length),
      ),
      representation:
          '$policy/$engine/${text.recognition ?? 'extracted'}/${text.digest!}',
    );
  }

  PdfAddress? resolveAddress(PdfAddress address, PdfText text) {
    if (!accepts(address) ||
        text.status != PdfTextStatus.candidate ||
        address.character > text.source.length) {
      return null;
    }
    final resolved = addressFor(address.sourcePage, text, address.character);
    return address.character == 0 ||
            address.representation == resolved.representation
        ? resolved
        : null;
  }

  @override
  ReaderAddress? restore(Map<String, dynamic> value) {
    if (value['version'] != 1 || value['original'] != originalDigest) {
      return null;
    }
    final address = decodeAddress(value);
    return accepts(address) ? address : null;
  }
}

typedef PdfTextLease = Future<PdfText?> Function(
  Future<PdfText> Function(VerifiedFile original, bool Function() owned) read,
);

/// Gives the text of pages whose text layer cannot be read, by recognizing
/// the page. Recognition takes seconds, so only the reflow view and search
/// ask for it, through [PdfBook.text].
abstract class PdfTextSupply {
  /// Whether this reader waits for a page that is recognized.
  ValueListenable<bool> get recognizing;
  void bind(PdfTextLease lease);

  /// Stops every wait of this reader. A page that started still finishes.
  void cancel();

  /// The text of [page] of [book] for reading: [extracted], the page's text
  /// layer, when it is a candidate, and otherwise the recognized text, whose
  /// status says whether the page reflows, or a [PdfTextStatus.failed] text.
  Future<PdfText> text(PdfBook book, int page, PdfText extracted);

  /// The word geometry of [page] of [book], whose text layer [extracted] is
  /// not a candidate, from Tesseract's layout pass. The layout pass of the
  /// page that a reader shows goes before every other waiting page. Null
  /// when the page has no geometry: [extracted] is a candidate, the layout
  /// pass failed, or this reader stopped waiting.
  ///
  /// A [background] layout pass, such as the book survey's, waits behind all
  /// other work and does not count as waiting for [recognizing]. A request
  /// for the shown page joins it and moves it to the front.
  Future<PageGeometry?> geometry(
    PdfBook book,
    int page,
    PdfText extracted, {
    bool background = false,
  });

  /// The text of [page] for reading, as [text] gives it, and for each word
  /// of [geometry], the page's geometry, its range of that text. The
  /// attachment is null when the text is not a recognized candidate.
  Future<({PdfText text, TextAttachment? attachment})> attachedText(
    PdfBook book,
    int page,
    PdfText extracted,
    PageGeometry geometry,
  );
  Future<void> close();
}

class PdfRuntime {
  PdfRuntime._();
  static final PdfRuntime instance = PdfRuntime._();
  Future<void>? _initialization;
  Future<void> _admission = Future.value();
  final Set<_NativePdfBook> _books = {};

  Future<T> _admit<T>(Future<T> Function() action) {
    if (RootIsolateToken.instance == null) {
      throw StateError('Native PDF work must run on the application isolate.');
    }
    final operation = _admission.then((_) => action());
    _admission = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }

  /// Opens the PDF file at [path], whose SHA-256 is [digest]. Downloads
  /// computed the digest when the download completed, so the open does not
  /// hash the file again. PDFium reads the file itself, so its bytes never
  /// come into this isolate (boo-yjq6). The open measures only the first
  /// page, and the book measures each other page when it first uses it
  /// (boo-yjq6). Each page text is prepared through [hop].
  ///
  /// NOTE: PDFium keeps the file open and reads its pages after the
  /// Downloads read that gave [path] ended. That is safe because Downloads
  /// replaces a file by a rename and removes it by an unlink: the open
  /// handle keeps the verified bytes. A removed PDF's space returns when
  /// the book closes.
  Future<PdfBook> open(
    String path,
    String digest, {
    PdfTextSupply? textSupply,
    IsolateHop hop = compute,
  }) => _admit(() async {
    await (_initialization ??= pdfrxFlutterInitialize());
    final document = await native.PdfDocument.openFile(
      path,
      useProgressiveLoading: true,
    );
    if (document.isEncrypted || document.pages.isEmpty) {
      await document.dispose();
      throw const FormatException(
        'Encrypted or empty PDFs are not supported. The original download was kept.',
      );
    }
    final book = _NativePdfBook(this, document, digest, textSupply, hop);
    _books.add(book);
    return book;
  });

  /// The text outline of the PDF file at [path], from its bookmarks and its
  /// text layer (see [measurePdfOutline]). Its PDFium work runs on pdfrx's
  /// worker as background work, beside the open books, and [shutdown]
  /// waits for it.
  Future<TextOutline> measureOutline(String path) async {
    await _admit(() async {
      await (_initialization ??= pdfrxFlutterInitialize());
      // An open book initializes PDFium again after [shutdown] destroyed
      // it, and this work opens no book, so it initializes it here.
      await native.PdfrxEntryFunctions.instance.init();
    });
    final work = measurePdfOutline(path);
    _measuring.add(work);
    try {
      return await work;
    } finally {
      _measuring.remove(work);
    }
  }

  /// The outline measurements that run.
  final Set<Future<TextOutline>> _measuring = {};

  Future<void> shutdown() => _admit(() async {
    await Future.wait([
      ..._books.toList().map((book) => book.dispose()),
      for (final work in _measuring) work.then((_) {}, onError: (_) {}),
    ]);
    await native.PdfrxEntryFunctions.instance.stopBackgroundWorker();
    _initialization = null;
  });

  void _release(_NativePdfBook book) {
    assert(_books.contains(book));
    _books.remove(book);
  }

  void checkInvariants() {
    if (_books.isNotEmpty && _initialization == null ||
        _books.any((book) => !identical(book.owner, this) || book._disposed)) {
      throw StateError(
        'PDF documents must share one live application-isolate engine owner.',
      );
    }
  }
}

class _NativePdfBook extends PdfBook {
  _NativePdfBook(
    this.owner,
    this._document,
    this.originalDigest,
    this.textSupply,
    IsolateHop hop,
  ) : super(hop: hop);
  @override
  final PdfTextSupply? textSupply;
  final PdfRuntime owner;
  final native.PdfDocument _document;
  final Set<Future<void>> _work = {};
  final Map<int, Future<PreparedPdfPage>> _layers = {};

  /// The measurements of pages that run now, by page number.
  final Map<int, Future<void>> _pageMeasurements = {};
  Future<void>? _closing;
  bool _disposed = false;
  @override
  final String originalDigest;
  @override
  String get format => 'pdf';
  @override
  String get engine => 'pdfrx-0.9.0-pdfium-8125';
  @override
  String get policy => 'bookfin-pdf-source-pages-1';
  @override
  String get identity =>
      sha256.convert(utf8.encode('$policy/$engine/$originalDigest')).toString();
  @override
  int get pageCount => _document.pages.length;
  @override
  bool accepts(ReaderAddress address) =>
      address is PdfAddress && address.sourcePage <= pageCount;
  @override
  ReaderAddress decodeAddress(Map<String, dynamic> value) {
    if (value['page'] is! int ||
        value['character'] is! int ||
        value['quote'] is! String ||
        value['representation'] != null && value['representation'] is! String) {
      throw const FormatException('Invalid saved PDF source page.');
    }
    return PdfAddress(
      value['page'] as int,
      value['character'] as int,
      quote: value['quote'] as String,
      pageCount: pageCount,
      representation: value['representation'] as String?,
    );
  }

  /// Throws an [ArgumentError] when this PDF has no source page [number].
  void _check(int number) {
    if (number < 1 || number > pageCount) {
      throw ArgumentError('Choose a source page in this PDF.');
    }
  }

  /// Source page [number], measured.
  ///
  /// The open measured only the first page. Until PDFium measures another
  /// page, pdfrx gives it the size of a measured page as a guess, and it
  /// has no text and draws nothing. So the first use of a page measures it.
  /// Nothing needs the sizes of all pages: the book map counts pages.
  Future<native.PdfPage> _page(int number) async {
    _check(number);
    if (!_document.pages[number - 1].isLoaded) {
      // The block returns nothing: the removed future is this one, and
      // whenComplete would wait for it.
      await (_pageMeasurements[number] ??= _document
          .reloadPages(pageNumbersToReload: [number])
          .whenComplete(() {
            _pageMeasurements.remove(number);
          }));
    }
    final page = _document.pages[number - 1];
    if (!page.isLoaded) {
      throw StateError('PDFium did not measure page $number.');
    }
    return page;
  }

  Future<T> _run<T>(Future<T> Function() action) {
    if (_closing != null) {
      return Future.error(StateError('This PDF is closed.'));
    }
    final operation = Future<T>.sync(action);
    late final Future<void> settled;
    settled = operation.then<void>(
      (_) {
        _work.remove(settled);
      },
      onError: (Object _, StackTrace _) {
        _work.remove(settled);
      },
    );
    _work.add(settled);
    return operation;
  }

  @override
  Future<PdfText> text(int sourcePage) => _run(() async {
    final extracted = await textLayer(sourcePage);
    if (_closing != null) return extracted;
    return textSupply?.text(this, sourcePage, extracted) ?? extracted;
  });

  @override
  Future<PageGeometry?> geometry(int sourcePage, {bool background = false}) =>
      _run(() async {
        final layer = await _layer(sourcePage);
        final extracted = layer.text;
        if (extracted.status == PdfTextStatus.candidate) {
          return layer.words?.geometry;
        }
        if (_closing != null) return null;
        return textSupply?.geometry(
          this,
          sourcePage,
          extracted,
          background: background,
        );
      });

  @override
  Future<({PdfText text, TextAttachment? attachment})> attachedText(
    int sourcePage,
    PageGeometry geometry,
  ) => _run(() async {
    final layer = await _layer(sourcePage);
    final extracted = layer.text;
    if (extracted.status == PdfTextStatus.candidate) {
      return (text: extracted, attachment: layer.words?.attachment);
    }
    if (_closing != null) return (text: extracted, attachment: null);
    return textSupply?.attachedText(this, sourcePage, extracted, geometry) ??
        (text: extracted, attachment: null);
  });

  @override
  Future<PdfText> textLayer(int sourcePage) =>
      _layer(sourcePage).then((layer) => layer.text);

  /// The text layer of [sourcePage] with its words, from one hop. The book
  /// keeps the last 16 pages.
  Future<PreparedPdfPage> _layer(int sourcePage) {
    if (_closing != null) {
      return Future.error(StateError('This PDF is closed.'));
    }
    _check(sourcePage);
    if (_layers.length >= 16 && !_layers.containsKey(sourcePage)) {
      _layers.remove(_layers.keys.first);
    }
    return _layers.putIfAbsent(
      sourcePage,
      () => _run(() async {
        final page = await _page(sourcePage);
        final raw = await page.loadText();
        final source = raw?.fullText ?? '';
        if (source.length > _pageTextLimit) {
          return (
            text: const PdfText(
              source: '',
              text: '',
              sourceOffsets: [],
              status: PdfTextStatus.unreliable,
            ),
            words: null,
          );
        }
        // The boxes cross to the worker as one typed list. Packing them
        // takes about 4 ns a character on an M-series Mac. Sending the
        // PdfRect objects themselves costs this isolate about 30 times as
        // much: about 450 ms for a page at the size limit.
        final rects = raw?.charRects ?? const <native.PdfRect>[];
        final boxes = Float64List(rects.length * 4);
        for (var index = 0; index < rects.length; index++) {
          final rect = rects[index];
          boxes
            ..[index * 4] = rect.left
            ..[index * 4 + 1] = rect.top
            ..[index * 4 + 2] = rect.right
            ..[index * 4 + 3] = rect.bottom;
        }
        final prepared = await hop(preparePdfPage, (
          source: source,
          boxes: boxes,
          width: page.width,
          height: page.height,
        ));
        return page.rotation == native.PdfPageRotation.none
            ? prepared
            : (text: prepared.text, words: null);
      }),
    );
  }

  @override
  Future<PdfRaster> render(int sourcePage, double width) => _run(() async {
    if (!width.isFinite || width <= 0) {
      throw ArgumentError('PDF render width must be positive.');
    }
    final page = await _page(sourcePage);
    var fullWidth = width.clamp(120, 1600).toDouble();
    var fullHeight = page.height * fullWidth / page.width;
    if (fullHeight > 4000) {
      fullWidth *= 4000 / fullHeight;
      fullHeight = 4000;
    }
    final image = await page.render(
      fullWidth: fullWidth,
      fullHeight: fullHeight,
    );
    if (image == null) {
      throw Exception('The original PDF page could not be drawn.');
    }
    try {
      return PdfRaster(
        image.width,
        image.height,
        Uint8List.fromList(image.pixels),
      );
    } finally {
      image.dispose();
    }
  });

  @override
  Future<ui.Image> renderPart(
    int sourcePage,
    int pixelsPerPageUnit,
    ui.Rect area,
  ) => _run(() async {
    const side = WordBands.maxBandSide;
    final left = area.left.toInt(), top = area.top.toInt();
    final width = area.width.toInt(), height = area.height.toInt();
    if (pixelsPerPageUnit <= 0 ||
        left != area.left ||
        top != area.top ||
        width != area.width ||
        height != area.height ||
        width <= 0 ||
        height <= 0 ||
        width > side ||
        height > side) {
      throw ArgumentError(
        'Choose a part of the page with whole-pixel edges, at most $side '
        'pixels on each side.',
      );
    }
    final page = await _page(sourcePage);
    final image = await page.render(
      x: left,
      y: top,
      width: width,
      height: height,
      fullWidth: pixelsPerPageUnit.toDouble(),
      fullHeight: page.height * pixelsPerPageUnit / page.width,
    );
    if (image == null) {
      throw Exception('The original PDF page could not be drawn.');
    }
    try {
      // The engine copies the pixels from pdfium's buffer, and the buffer
      // is freed once the image exists.
      final done = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        image.pixels,
        width,
        height,
        ui.PixelFormat.bgra8888,
        done.complete,
      );
      return await done.future;
    } finally {
      image.dispose();
    }
  });

  @override
  Future<void> dispose() {
    textSupply?.cancel();
    return _closing ??= _dispose();
  }

  Future<void> _dispose() async {
    // The survey surveys no more pages, and keeps what it surveyed.
    await Future.wait([..._work, survey.close()]);
    try {
      await textSupply?.close();
    } finally {
      await _document.dispose();
      _disposed = true;
      owner._release(this);
    }
  }
}

/// Whether the extracted page [text] with its character [boxes] (see
/// [preparePdfPage]) cannot be trusted to read in order.
bool _outOfOrder(String text, Float64List boxes) {
  if (boxes.length != text.length * 4 ||
      text.contains('\uFFFD') ||
      text.contains('\u0000')) {
    return true;
  }
  double left(int index) => boxes[index * 4];
  double top(int index) => boxes[index * 4 + 1];
  double right(int index) => boxes[index * 4 + 2];
  double bottom(int index) => boxes[index * 4 + 3];
  final rows = <int, List<List<int>>>{};
  for (var index = 0; index < text.length; index++) {
    if (text[index].trim().isEmpty ||
        left(index) >= right(index) ||
        top(index) <= bottom(index)) {
      continue;
    }
    if (![
      left(index),
      right(index),
      top(index),
      bottom(index),
    ].every((value) => value.isFinite)) {
      return true;
    }
    final bucket = (bottom(index) / 3).floor();
    final row =
        [for (var key = bucket - 1; key <= bucket + 1; key++) ...?rows[key]]
            .where((row) => (bottom(row.first) - bottom(index)).abs() <= 3)
            .firstOrNull;
    if (row == null) {
      rows.putIfAbsent(bucket, () => []).add([index]);
    } else {
      row.add(index);
    }
  }
  var groups = 0;
  var shortGroups = 0;
  var parallelRows = 0;
  for (final row in rows.values.expand((bucket) => bucket)) {
    row.sort((first, second) => left(first).compareTo(left(second)));
    final parts = <List<int>>[];
    for (final index in row) {
      if (parts.isEmpty || left(index) - right(parts.last.last) > 18) {
        parts.add([index]);
      } else {
        parts.last.add(index);
      }
    }
    if (parts.length > 1) parallelRows++;
    for (final part in parts) {
      groups++;
      final phrase = text.substring(
        part.reduce((first, second) => first < second ? first : second),
        part.reduce((first, second) => first > second ? first : second) + 1,
      );
      if (phrase.trim().split(RegExp(r'\s+')).length <= 2) shortGroups++;
      for (var index = 1; index < part.length; index++) {
        if ((part[index] - part[index - 1]).abs() > 5) return true;
      }
    }
  }
  return parallelRows >= 3 || groups >= 4 && shortGroups / groups >= .8;
}

/// The median of [values], which is not empty.
double _median(Iterable<double> values) {
  final sorted = values.toList()..sort();
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2;
}
