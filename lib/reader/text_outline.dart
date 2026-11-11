import 'dart:convert';

import '../catalog/model.dart';
import 'book_map.dart';
import 'contents.dart';
import 'document.dart';
import 'epub/publication.dart';

/// One contents entry of a [TextOutline]: its title, its nesting from 0,
/// and its start in visible characters from the book's start.
typedef OutlineEntry = ({String title, int depth, int start});

/// The text outline of an ebook edition (docs/plans/cross-edition-places.md):
/// the contents entries that the reader lists, each with its start in
/// visible characters from the book's start, and the visible characters of
/// each part. A visible character is a character of the body text that is
/// not white space, as [BookMap] counts it. A part is an EPUB section of the
/// spine, or a PDF source page (see `pdfOutlineOf`).
///
/// The cross-edition matching pairs the entries with audio chapters, and
/// places reading places along the book by their characters.
class TextOutline {
  /// The outline of [parts] with [entries], which it lists in order of
  /// their starts. Entries that start at one place keep their order in
  /// [entries].
  TextOutline({
    required List<({String path, int characters})> parts,
    required List<OutlineEntry> entries,
  }) : parts = List.unmodifiable(parts),
       entries = List.unmodifiable(_byStart(entries)),
       _starts = _startsOf(parts);

  /// The outline that [toJson] wrote. Throws a [FormatException] when
  /// [value] is not one.
  factory TextOutline.fromJson(Map<String, dynamic> value) {
    Never invalid() => throw const FormatException('Not a text outline.');
    if (value case {'parts': final List parts, 'entries': final List entries}) {
      return TextOutline(
        parts: [
          for (final part in parts)
            switch (part) {
              [final String path, final int characters] when characters >= 0 =>
                (path: path, characters: characters),
              _ => invalid(),
            },
        ],
        entries: [
          for (final entry in entries)
            switch (entry) {
              [final String title, final int depth, final int start]
                  when depth >= 0 && start >= 0 =>
                (title: title, depth: depth, start: start),
              _ => invalid(),
            },
        ],
      );
    }
    invalid();
  }

  /// Each part in spine order: its resource path and its visible characters.
  final List<({String path, int characters})> parts;

  /// The contents entries in order of their starts. Entries that start at
  /// one place keep their order in the contents.
  final List<OutlineEntry> entries;

  /// Where each part starts, with the book's length after the last part.
  final List<int> _starts;

  /// [entries] in order of their starts, by a stable sort.
  static List<OutlineEntry> _byStart(List<OutlineEntry> entries) {
    final order = [for (var index = 0; index < entries.length; index++) index]
      ..sort((a, b) {
        final by = entries[a].start.compareTo(entries[b].start);
        return by != 0 ? by : a.compareTo(b);
      });
    return [for (final index in order) entries[index]];
  }

  static List<int> _startsOf(List<({String path, int characters})> parts) {
    final starts = [0];
    for (final part in parts) {
      starts.add(starts.last + part.characters);
    }
    return starts;
  }

  /// The visible characters of the whole book.
  int get length => _starts.last;

  /// Where the reading place [place] lies, in visible characters from the
  /// book's start, or null when its anchor names no part of this book or
  /// no share of its section, as places that early builds saved do not.
  /// A PDF place names its source page, and lies at the page's start, as
  /// the reader shows a page from its start.
  double? charactersOf(TextPosition place) {
    final Object? anchor;
    try {
      anchor = jsonDecode(place.anchor);
    } on FormatException {
      return null;
    }
    if (anchor
        case {'resource': final String resource, 'progress': final num progress}
        when progress >= 0 && progress <= 1) {
      final part = parts.indexWhere((part) => part.path == resource);
      if (part < 0) return null;
      return _starts[part] + parts[part].characters * progress.toDouble();
    }
    if (anchor case {'page': final int page}
        when page >= 1 &&
            page <= parts.length &&
            parts[page - 1].path == 'page:$page') {
      return _starts[page - 1].toDouble();
    }
    return null;
  }

  /// The place at [characters] from the book's start: the last part that
  /// starts there or before, and the share of its visible characters before
  /// the place. A place at the end of one part is the start of the next. A
  /// place outside the book is its start or its end.
  BookPlace placeAt(double characters) {
    if (parts.isEmpty) return (part: 0, progress: 0);
    final at = characters.clamp(0, length).toDouble();
    var part = parts.length - 1;
    while (part > 0 && _starts[part] > at) {
      part--;
    }
    final size = parts[part].characters;
    return (
      part: part,
      progress: size > 0 ? ((at - _starts[part]) / size).clamp(0.0, 1.0) : 0.0,
    );
  }

  /// The title of the last contents entry that starts at [characters] from
  /// the book's start or before, or null before the first entry. The book
  /// map names a place's chapter by the same rule.
  String? chapterAt(double characters) {
    String? title;
    for (final entry in entries) {
      if (entry.start > characters) break;
      title = entry.title;
    }
    return title;
  }

  Map<String, dynamic> toJson() => {
    'parts': [
      for (final part in parts) [part.path, part.characters],
    ],
    'entries': [
      for (final entry in entries) [entry.title, entry.depth, entry.start],
    ],
  };
}

/// Whether the character [code] is white space, which the book map leaves
/// out of the visible characters: exactly what `\s` matches in a Dart
/// regular expression.
bool isWhiteSpace(int code) =>
    code >= 0x09 && code <= 0x0D ||
    code == 0x20 ||
    code == 0xA0 ||
    code == 0x1680 ||
    code >= 0x2000 && code <= 0x200A ||
    code == 0x2028 ||
    code == 0x2029 ||
    code == 0x202F ||
    code == 0x205F ||
    code == 0x3000 ||
    code == 0xFEFF;

/// The text outline of [publication]. It parses every section, so run it
/// in a worker isolate.
TextOutline measureTextOutline(Publication publication) {
  final contents = listedContents(publication);
  final targets = contentsTargets(publication, contents);
  final wanted = <int, Set<String>>{};
  for (final (entry: _, :part, :id) in targets) {
    if (id != null) (wanted[part] ??= {}).add(id);
  }
  final counts = [
    for (final (index, path) in publication.spine.indexed)
      countSection(publication.resources[path]!, wanted[index] ?? const {}),
  ];
  final parts = [
    for (final (index, path) in publication.spine.indexed)
      (path: path, characters: counts[index].visible),
  ];
  final starts = TextOutline._startsOf(parts);
  final entries = [
    for (final (:entry, :part, :id) in targets)
      (
        title: contents[entry].title,
        depth: contents[entry].depth,
        start: starts[part] + (id == null ? 0 : counts[part].before[id] ?? 0),
      ),
  ];
  return TextOutline(parts: parts, entries: entries);
}
