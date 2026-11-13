// PDF outline calculations are shared by native and browser callers.
// Only native builds extract an outline from a PDF file.
import 'text_outline.dart';

export 'pdf_outline_stub.dart' if (dart.library.io) 'pdf_outline_io.dart';

/// A bookmark of a PDF: its [title], its nesting from 0, the source [page]
/// from 1 that it goes to, and the visible characters of that page's text
/// layer [above] the place where it goes.
typedef PdfBookmark = ({String title, int depth, int page, int above});

/// The visible characters that a page without a text layer counts as in a
/// scanned book: a printed book page of about 330 words of 4.8 letters.
const scannedPageCharacters = 1600;

/// The text outline of a PDF whose source pages hold [visible] characters
/// in their text layers, in page order, and whose outline lists
/// [bookmarks].
///
/// Each source page is a part, `page:N`, as a PDF place names its page. A
/// page without a text layer holds no characters when most pages have one:
/// it is a picture or a blank page. In a scanned book, where most pages
/// have none, each such page counts as [scannedPageCharacters], so places
/// fall by pages. Bookfin does not recognize a whole book's text for this.
/// A bookmark is a contents entry at its depth, in the order of the book.
/// It starts at its page, after the characters above its place there. A
/// bookmark to a page outside the book is left out, and so is a bookmark
/// without a title, which names no chapter.
TextOutline pdfOutlineOf(List<int> visible, List<PdfBookmark> bookmarks) {
  final scan = visible.where((count) => count > 0).length * 2 < visible.length;
  final parts = [
    for (final (index, count) in visible.indexed)
      (
        path: 'page:${index + 1}',
        characters: count == 0 && scan ? scannedPageCharacters : count,
      ),
  ];
  final starts = [0];
  for (final part in parts) {
    starts.add(starts.last + part.characters);
  }
  return TextOutline(
    parts: parts,
    entries: [
      for (final (:title, :depth, :page, :above) in bookmarks)
        if (page >= 1 && page <= parts.length && title.trim().isNotEmpty)
          (
            title: title.trim(),
            depth: depth,
            start:
                starts[page - 1] +
                above.clamp(0, parts[page - 1].characters).toInt(),
          ),
    ],
  );
}
