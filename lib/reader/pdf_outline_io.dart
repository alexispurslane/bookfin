// The text outline of a PDF edition (docs/plans/cross-edition-places.md,
// step 8 of the order of work): its bookmarks as contents entries, and the
// visible characters of each source page's text layer.
//
// The PDFium work runs on pdfrx's worker isolate, where every PDFium call
// of the app runs, one after another, so the UI isolate only receives
// counts. It runs as background work, in slices of about 8 ms, so that the
// reader's pages draw first. It opens its own handle of the file, so it
// does not depend on the reader's open book.
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:pdfium_dart/pdfium_dart.dart' as pdfium_bindings;
import 'package:pdfrx_engine/pdfrx_engine.dart' show Pdfrx, PdfrxEntryFunctions;

import 'pdf_outline.dart' show pdfOutlineOf;
import 'text_outline.dart';

/// The text outline of the PDF file at [path] (see [pdfOutlineOf]). It
/// throws a [FormatException] when PDFium cannot open the file, as for an
/// encrypted or damaged PDF. pdfrx must be initialized.
Future<TextOutline> measurePdfOutline(String path) =>
    Pdfrx.runAsBackgroundWork(() async {
      final compute = PdfrxEntryFunctions.instance.compute;
      final opened = await compute(_open, path);
      if (opened == null) {
        throw const FormatException('PDFium cannot open this PDF.');
      }
      try {
        // The bookmarks that name a height on their page, each as its index
        // in the outline and its height, by page index.
        final tops = <int, List<(int, double)>>{};
        for (final (index, (title: _, depth: _, :page, :top))
            in opened.marks.indexed) {
          if (top != null) (tops[page] ??= []).add((index, top));
        }
        final visible = <int>[];
        final above = <int, int>{};
        while (visible.length < opened.pages) {
          final slice = await compute(_count, (
            document: opened.document,
            from: visible.length,
            tops: tops,
          ));
          visible.addAll(slice.visible);
          above.addAll(slice.above);
        }
        // NOTE: Engine rule 1. This walks the bookmarks and the pages once,
        // a few hundred of each for a long book, which costs far less than
        // a hop to another isolate.
        return pdfOutlineOf(visible, [
          for (final (index, (:title, :depth, :page, top: _))
              in opened.marks.indexed)
            (
              title: title,
              depth: depth,
              page: page + 1,
              above: above[index] ?? 0,
            ),
        ]);
      } finally {
        await compute(_close, opened.document);
      }
    });

/// A bookmark as PDFium gives it: its title, its depth, the index of its
/// page from 0, and the height of its place on the page, in PDF points
/// from the page's bottom, when the bookmark names one.
typedef _Mark = ({String title, int depth, int page, double? top});

/// PDFium, on pdfrx's worker isolate, where it is loaded on first use. pdfrx
/// gives the worker the module path that the app set.
final _pdfium = pdfium_bindings.getPdfium(modulePath: Pdfrx.pdfiumModulePath);

/// How deep the bookmarks nest at most before the rest of a branch is left
/// out. Each level costs one frame of the stack.
const _deepestBookmark = 32;

/// How many bookmarks a PDF has at most before the rest are left out, as in
/// a damaged outline that loops.
const _mostBookmarks = 10000;

/// On PDFium's worker: opens the PDF at [path], and gives its document
/// handle, its page count and its bookmarks in the order of its outline,
/// or null when PDFium cannot open it.
({int document, int pages, List<_Mark> marks})? _open(String path) {
  final name = path.toNativeUtf8();
  try {
    final document = _pdfium.FPDF_LoadDocument(name.cast(), nullptr);
    if (document == nullptr) return null;
    try {
      return (
        document: document.address,
        pages: _pdfium.FPDF_GetPageCount(document),
        marks: _marks(document),
      );
    } catch (_) {
      _pdfium.FPDF_CloseDocument(document);
      rethrow;
    }
  } finally {
    malloc.free(name);
  }
}

/// On PDFium's worker: the bookmarks of [document] that go to a page, in
/// the order of its outline.
List<_Mark> _marks(pdfium_bindings.FPDF_DOCUMENT document) {
  final marks = <_Mark>[];
  final seen = <int>{};
  final found = calloc<pdfium_bindings.FPDF_BOOL>(3);
  final at = calloc<pdfium_bindings.FS_FLOAT>(3);
  void walk(pdfium_bindings.FPDF_BOOKMARK first, int depth) {
    var bookmark = first;
    while (bookmark != nullptr &&
        seen.add(bookmark.address) &&
        seen.length <= _mostBookmarks) {
      var dest = _pdfium.FPDFBookmark_GetDest(document, bookmark);
      if (dest == nullptr) {
        final action = _pdfium.FPDFBookmark_GetAction(bookmark);
        if (action != nullptr &&
            _pdfium.FPDFAction_GetType(action) ==
                pdfium_bindings.PDFACTION_GOTO) {
          dest = _pdfium.FPDFAction_GetDest(document, action);
        }
      }
      final page = dest == nullptr
          ? -1
          : _pdfium.FPDFDest_GetDestPageIndex(document, dest);
      if (page >= 0) {
        // Only an /XYZ destination names its height, and only when its top
        // is not left unchanged.
        final named =
            _pdfium.FPDFDest_GetLocationInPage(
                  dest,
                  found,
                  found + 1,
                  found + 2,
                  at,
                  at + 1,
                  at + 2,
                ) !=
                0 &&
            found[1] != 0;
        marks.add((
          title: _title(bookmark),
          depth: depth,
          page: page,
          top: named ? at[1] : null,
        ));
      }
      if (depth + 1 < _deepestBookmark) {
        walk(_pdfium.FPDFBookmark_GetFirstChild(document, bookmark), depth + 1);
      }
      bookmark = _pdfium.FPDFBookmark_GetNextSibling(document, bookmark);
    }
  }

  try {
    walk(_pdfium.FPDFBookmark_GetFirstChild(document, nullptr), 0);
    return marks;
  } finally {
    calloc
      ..free(found)
      ..free(at);
  }
}

/// On PDFium's worker: the title of [bookmark].
String _title(pdfium_bindings.FPDF_BOOKMARK bookmark) {
  final size = _pdfium.FPDFBookmark_GetTitle(bookmark, nullptr, 0);
  if (size <= 2) return '';
  final buffer = calloc<Uint8>(size);
  try {
    _pdfium.FPDFBookmark_GetTitle(bookmark, buffer.cast(), size);
    return buffer.cast<Utf16>().toDartString();
  } finally {
    calloc.free(buffer);
  }
}

/// How long one slice of [_count] runs before it hands the worker back, so
/// that a page that the reader asks for waits at most about this long.
const _slice = Duration(milliseconds: 8);

/// On PDFium's worker: the visible characters of the text layer of each
/// page of [work]'s document from page index `from` on, for at least one
/// page and for about [_slice]. `tops` lists bookmarks by page index, each
/// as its index in the outline and the height of its place. For each such
/// bookmark, by its index, it also gives the page's visible characters
/// above that height: those whose middle lies higher on the page.
({List<int> visible, Map<int, int> above}) _count(
  ({int document, int from, Map<int, List<(int, double)>> tops}) work,
) {
  final document = pdfium_bindings.FPDF_DOCUMENT.fromAddress(work.document);
  final pages = _pdfium.FPDF_GetPageCount(document);
  final visible = <int>[];
  final above = <int, int>{};
  final box = calloc<Double>(4);
  final clock = Stopwatch()..start();
  try {
    for (var index = work.from; index < pages; index++) {
      if (visible.isNotEmpty && clock.elapsed > _slice) break;
      final tops = work.tops[index] ?? const <(int, double)>[];
      for (final (mark, _) in tops) {
        above[mark] = 0;
      }
      var count = 0;
      final page = _pdfium.FPDF_LoadPage(document, index);
      if (page != nullptr) {
        final text = _pdfium.FPDFText_LoadPage(page);
        if (text != nullptr) {
          final characters = _pdfium.FPDFText_CountChars(text);
          for (var character = 0; character < characters; character++) {
            if (isWhiteSpace(_pdfium.FPDFText_GetUnicode(text, character))) {
              continue;
            }
            count++;
            if (tops.isEmpty) continue;
            if (_pdfium.FPDFText_GetCharBox(
                  text,
                  character,
                  box,
                  box + 1,
                  box + 2,
                  box + 3,
                ) ==
                0) {
              continue;
            }
            final middle = (box[2] + box[3]) / 2;
            for (final (mark, top) in tops) {
              if (middle > top) above[mark] = above[mark]! + 1;
            }
          }
          _pdfium.FPDFText_ClosePage(text);
        }
        _pdfium.FPDF_ClosePage(page);
      }
      visible.add(count);
    }
    return (visible: visible, above: above);
  } finally {
    calloc.free(box);
  }
}

/// On PDFium's worker: closes the document of [_open].
void _close(int document) => _pdfium.FPDF_CloseDocument(
  pdfium_bindings.FPDF_DOCUMENT.fromAddress(document),
);
