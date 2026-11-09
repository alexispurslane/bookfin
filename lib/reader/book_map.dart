import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:xml/xml_events.dart';

import '../foundation/hop.dart';
import 'book_pages.dart';
import 'document.dart';
import 'pdf.dart';

/// A place that the scrub bar points at, given as a fraction of the whole
/// book and as the part of the book that holds it.
@immutable
class BookTarget {
  const BookTarget({
    required this.fraction,
    required this.part,
    required this.progress,
    this.chapter,
    this.page,
  });

  /// Where the place sits in the whole book, from 0 at its start to 1 at its
  /// end.
  final double fraction;

  /// The index of the part that holds the place: a section of an EPUB's
  /// spine, from 0, or a PDF's source page minus one.
  final int part;

  /// How far through its part the place is, from 0 to 1. In an EPUB this is
  /// the text progress through the section (see [BookMap]).
  final double progress;

  /// The title of the contents entry where the place is, or null before the
  /// first chapter and in a PDF.
  final String? chapter;

  /// The number of the page that holds the place among the pages of the
  /// whole book, from 1, or null while [BookMap.pages] is not known.
  final int? page;

  @override
  bool operator ==(Object other) =>
      other is BookTarget &&
      other.fraction == fraction &&
      other.part == part &&
      other.progress == progress &&
      other.chapter == chapter &&
      other.page == page;

  @override
  int get hashCode => Object.hash(fraction, part, progress, chapter, page);
}

/// Where places sit along the whole length of one open book, as fractions
/// from 0 at its start to 1 at its end. The scrub bar draws the book with
/// it. The map serves the bar only: the reader still saves and restores each
/// place by its exact address.
///
/// A book is a row of parts, and the bar gives each page of the book an
/// equal share. An EPUB's parts are the sections of its spine. A section
/// whose true pages are known ([paged]) takes a share by its pages, and a
/// place inside it sits on the share of the page that holds it, at its text
/// progress through that page. A section whose pages are not known yet
/// takes the pages that its bytes estimate, at the pages per byte of the
/// sections whose pages are known, and at least one page. Before any
/// section's pages are known, each takes its share of the spine's bytes.
/// Sizes cost nothing to read when a book opens. A place inside such a
/// section sits at its text progress: the share of the section's visible
/// characters, white space left out, that come before it. A PDF's parts
/// are its source pages, one page each, and a place sits at the end of its
/// page.
///
/// Once every part's pages are known, the map names the page at each place
/// of the bar ([BookTarget.page]), and the place that it gives for a
/// fraction is on that page.
class BookMap {
  BookMap._(this._sizes, this._parts, this._chapters, this._pages);

  /// The map of a PDF with [pages] source pages. A PDF's contents list its
  /// source pages, which are not chapters, so the map has no chapters.
  BookMap.pages(int pages)
    : this._(
        List.filled(pages, 1),
        const {},
        const [],
        BookPages([
          for (var page = 0; page < pages; page++)
            (starts: const [0], length: 0),
        ]),
      );

  /// Measures [document], with the chapters that its [contents] list, or
  /// completes with null when the document is neither an EPUB nor a PDF.
  /// The chapters of a large book are measured in another isolate through
  /// [hop].
  static Future<BookMap?> of(
    ReaderDocument document,
    List<ContentsEntry> contents, {
    IsolateHop hop = compute,
  }) async {
    if (document is PdfBook) return BookMap.pages(document.pageCount);
    if (document is! EpubDocument) return null;
    final publication = document.publication;
    final spine = publication.spine;
    final sizes = [
      for (final path in spine) publication.resources[path]!.length,
    ];
    final parts = {for (final (index, path) in spine.indexed) path: index};

    // Each contents entry points at a section, and perhaps at an element in
    // it by its id.
    final package = Uri(
      scheme: 'https',
      host: 'book',
      path: '/${publication.packagePath}',
    );
    final entries = <({String title, int part, String? id})>[];
    for (final entry in contents) {
      final Uri href;
      try {
        href = package.resolve(entry.href);
      } on FormatException {
        continue;
      }
      final part = parts[href.pathSegments.join('/')];
      if (part == null) continue;
      entries.add((
        title: entry.title,
        part: part,
        id: href.hasFragment && href.fragment.isNotEmpty
            ? Uri.decodeComponent(href.fragment)
            : null,
      ));
    }
    final wanted = <int, Set<String>>{};
    for (final (title: _, :part, :id) in entries) {
      if (id != null) (wanted[part] ??= {}).add(id);
    }
    final sections = [
      for (final MapEntry(key: part, value: ids) in wanted.entries)
        (bytes: publication.resources[spine[part]]!, ids: ids),
    ];
    final bytes = sections.fold(
      0,
      (sum, section) => sum + section.bytes.length,
    );
    // NOTE: A hop costs a few milliseconds, more than reading a small book.
    final measured = bytes < 64 << 10
        ? _measureIds(sections)
        : await hop(_measureIds, sections);
    final progress = {
      for (final (index, part) in wanted.keys.indexed) part: measured[index],
    };
    final chapters = [
      for (final (:title, :part, :id) in entries)
        (title: title, part: part, progress: progress[part]?[id] ?? 0.0),
    ];
    // Entries that start at one place keep their order in the contents.
    final order = [for (var index = 0; index < chapters.length; index++) index]
      ..sort((a, b) {
        final (first, second) = (chapters[a], chapters[b]);
        return switch ((
          first.part.compareTo(second.part),
          first.progress.compareTo(second.progress),
        )) {
          (0, 0) => a.compareTo(b),
          (0, final order) => order,
          (final order, _) => order,
        };
      });
    return BookMap._(
      sizes,
      parts,
      List.unmodifiable([for (final index in order) chapters[index]]),
      null,
    );
  }

  /// This map with the true pages of the parts that [pages] knows, in the
  /// current page settings. The chapters stay where the contents point.
  BookMap paged(BookPages pages) => BookMap._(_sizes, _parts, _chapters, pages);

  /// The bytes of each part, which estimate its pages until they are known.
  final List<int> _sizes;

  /// The index of each EPUB section by its resource path.
  final Map<String, int> _parts;

  /// The chapters that the contents list, by where they start, in order.
  final List<({String title, int part, double progress})> _chapters;

  /// The true pages of the parts whose pages are known, or null when none
  /// are.
  final BookPages? _pages;

  /// Where each part starts, with 1 after the last part.
  late final List<double> _starts = () {
    final known = _pages?.parts;
    var pages = 0;
    var bytes = 0;
    for (final (index, part) in (known ?? const []).indexed) {
      if (part == null) continue;
      pages += part.starts.length;
      bytes += _sizes[index];
    }
    // Each part's pages, known or estimated, or its bytes before any part's
    // pages are known.
    final weights = [
      for (final (index, size) in _sizes.indexed)
        if (known?[index] case final part?)
          part.starts.length.toDouble()
        else if (pages > 0 && bytes > 0)
          math.max(1.0, size * pages / bytes)
        else
          size.toDouble(),
    ];
    final whole = weights.fold(0.0, (sum, weight) => sum + weight);
    final starts = <double>[0];
    var before = 0.0;
    for (final (index, weight) in weights.indexed) {
      before += weight;
      starts.add(whole > 0 ? before / whole : (index + 1) / weights.length);
    }
    return starts;
  }();

  /// The chapters that the contents list, by where they start, in order.
  late final List<({String title, double start})> chapters = List.unmodifiable([
    for (final (:title, :part, :progress) in _chapters)
      (title: title, start: _within(part, progress)),
  ]);

  /// The number of pages of the whole book once every part's pages are
  /// known: a PDF's source pages, or an EPUB's true pages in the current
  /// page settings. Null before then.
  int? get pages => _pages?.count;

  /// Where [place] sits in the book, or null when the place is not in this
  /// book.
  double? fractionOf(ReaderAddress place) {
    final (part, through) = switch (place) {
      EpubAddress(:final location) => (
        _parts[location.resource],
        location.progress ?? 0.0,
      ),
      // The shown page counts as read, so the last page fills the bar.
      PdfAddress(:final sourcePage) => (sourcePage - 1, 1.0),
    };
    if (part == null || part < 0 || part + 1 >= _starts.length) return null;
    return _within(part, through);
  }

  /// Where the place [place] sits in the book, the reverse of [targetAt]. A
  /// part outside the book is its start or its end.
  double fractionAt(BookPlace place) {
    final part = place.part.clamp(0, _starts.length - 2);
    if (part != place.part) return place.part < 0 ? 0 : 1;
    return _within(part, place.progress.clamp(0.0, 1.0));
  }

  /// Where the chapter that a chapter arrow goes to from the [shown] page
  /// starts, given by the address that the viewport reported for it, and
  /// [end], the place of the page's last visible character where the shown
  /// page knows it.
  ///
  /// Forward, that is the first chapter that starts after the shown page:
  /// after [end], else after its first place. So a chapter that starts on
  /// the shown page, which is already in view, is skipped (t6-0cjf). Back, it is the last chapter that starts before the page's
  /// first place: the start of the chapter that holds it, or the chapter
  /// before when the page starts that chapter. The book's start counts as a
  /// chapter start, so back reaches the text before the first chapter.
  ///
  /// Null when no chapter starts that way, or when [shown] is not in this
  /// book.
  double? chapterStep(
    ReaderAddress shown, {
    required bool forward,
    BookPlace? end,
  }) {
    final at = fractionOf(shown);
    if (at == null) return null;
    // Places measured on two paths can differ in the last bits.
    const near = 1e-9;
    if (forward) {
      final last = end == null ? at : fractionAt(end);
      for (final chapter in chapters) {
        if (chapter.start > last + near) return chapter.start;
      }
      return null;
    }
    double? before = at > near ? 0 : null;
    for (final chapter in chapters) {
      if (chapter.start >= at - near) break;
      before = chapter.start;
    }
    return before;
  }

  /// Where the place [through] of the way through part [part] sits, by the
  /// rule that [targetAt] reverses, so that equal places give equal
  /// fractions.
  double _within(int part, double through) {
    final start = _starts[part];
    final share = _starts[part + 1] - start;
    final pages = _pages?.parts[part];
    if (pages == null || pages.length == 0) return start + share * through;
    final starts = pages.starts;
    // The place names a visible character, at most the last one, as the
    // reader's placeAt reads it. A saved place keeps six decimals of its
    // progress, so it rounds to that character. A page whose first drawn
    // line follows text that the book hides saves progress 1, and still
    // sits on the part's last page.
    final character = math.min(
      (through * pages.length).round(),
      pages.length - 1,
    );
    final page = _pageHolding(starts, character);
    final first = starts[page];
    final end = page + 1 < starts.length ? starts[page + 1] : pages.length;
    final inPage = end > first
        ? ((character - first) / (end - first)).clamp(0.0, 1.0)
        : 0.0;
    return start + share * (page + inPage) / starts.length;
  }

  /// The place at [fraction] of the book. A fraction outside 0 to 1 is the
  /// book's start or end.
  BookTarget targetAt(double fraction) {
    final at = fraction.clamp(0.0, 1.0);
    // The last part that starts at or before the place.
    var low = 0;
    var high = _starts.length - 2;
    while (low < high) {
      final middle = (low + high + 1) ~/ 2;
      if (_starts[middle] <= at) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    final share = _starts[low + 1] - _starts[low];
    final through = share > 0
        ? ((at - _starts[low]) / share).clamp(0.0, 1.0)
        : 0.0;
    final chapter = chapters.lastWhere(
      (chapter) => chapter.start <= at,
      orElse: () => (title: '', start: -1),
    );
    final (progress, page) = _onPage(low, through);
    return BookTarget(
      fraction: at,
      part: low,
      progress: progress,
      chapter: chapter.start < 0 ? null : chapter.title,
      page: page == null ? null : _pages!.numberOf(low, page),
    );
  }

  /// The text progress at [through] of the way along part [part]'s share of
  /// the bar, and the index of the page that holds it, or null when the
  /// part's pages are not known.
  ///
  /// Each page takes an equal share. The progress names a visible character
  /// of the page, a quarter of the way into it, so that the reader goes to
  /// that character and so to that page. A page without text has none: its
  /// share names the first character after it, on the page that holds it.
  (double, int?) _onPage(int part, double through) {
    final pages = _pages?.parts[part];
    if (pages == null) return (through, null);
    final starts = pages.starts;
    if (pages.length == 0) return (through, 0);
    // A tiny tolerance, so that the start of a page's share, reached from
    // the page's first character, names that page.
    final along = through * starts.length + 1e-9;
    final index = math.min(along.floor(), starts.length - 1);
    final first = starts[index];
    final end = index + 1 < starts.length ? starts[index + 1] : pages.length;
    final int character = end > first
        ? first +
              math.min(
                ((along - index).clamp(0.0, 1.0) * (end - first)).floor(),
                end - first - 1,
              )
        : math.min(first, pages.length - 1);
    return ((character + .25) / pages.length, _pageHolding(starts, character));
  }

  /// The index of the last page of [starts] that starts at or before the
  /// visible character [character].
  static int _pageHolding(List<int> starts, int character) {
    var low = 0;
    var high = starts.length - 1;
    while (low < high) {
      final middle = (low + high + 1) >> 1;
      if (starts[middle] <= character) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    return low;
  }
}

/// For each section, the text progress at which each wanted element starts.
/// An id that the section lacks has no progress.
List<Map<String, double>> _measureIds(
  List<({Uint8List bytes, Set<String> ids})> sections,
) => [for (final (:bytes, :ids) in sections) _measureSection(bytes, ids)];

final _space = RegExp(r'\s');

/// Counts the visible characters of the section's body, white space left
/// out, the same way the reader does, and notes how many come before each
/// element in [ids].
Map<String, double> _measureSection(Uint8List bytes, Set<String> ids) {
  final before = <String, int>{};
  var visible = 0;
  var body = false;
  try {
    for (final event in parseEvents(utf8.decode(bytes, allowMalformed: true))) {
      switch (event) {
        case XmlStartElementEvent(:final localName, :final attributes):
          if (localName == 'body') body = true;
          for (final attribute in attributes) {
            if (attribute.localName == 'id' && ids.contains(attribute.value)) {
              before.putIfAbsent(attribute.value, () => visible);
            }
          }
        case XmlTextEvent(:final value) when body:
          visible += value.replaceAll(_space, '').length;
        case XmlCDATAEvent(:final value) when body:
          visible += value.replaceAll(_space, '').length;
        default:
      }
    }
  } on Exception {
    // An admitted section always parses. If one does not, its chapters start
    // at the section's start.
    return const {};
  }
  return {
    for (final MapEntry(key: id, value: count) in before.entries)
      id: visible > 0 ? count / visible : 0,
  };
}
