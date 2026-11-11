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
/// spine.
///
/// The cross-edition matching pairs the entries with audio chapters, and
/// places reading places along the book by their characters.
class TextOutline {
  TextOutline({
    required List<({String path, int characters})> parts,
    required List<OutlineEntry> entries,
  }) : parts = List.unmodifiable(parts),
       entries = List.unmodifiable(entries),
       _starts = _startsOf(parts);

  /// The outline that [toJson] wrote. Throws a [FormatException] or a
  /// [TypeError] when [value] is not one.
  factory TextOutline.fromJson(Map<String, dynamic> value) => TextOutline(
    parts: [
      for (final part in value['parts'] as List)
        (path: part[0] as String, characters: part[1] as int),
    ],
    entries: [
      for (final entry in value['entries'] as List)
        (
          title: entry[0] as String,
          depth: entry[1] as int,
          start: entry[2] as int,
        ),
    ],
  );

  /// Each part in spine order: its resource path and its visible characters.
  final List<({String path, int characters})> parts;

  /// The contents entries in order of their starts. Entries that start at
  /// one place keep their order in the contents.
  final List<OutlineEntry> entries;

  /// Where each part starts, with the book's length after the last part.
  final List<int> _starts;

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
  /// book's start, or null when its anchor names no section of this book or
  /// no share of its section, as places that early builds saved do not.
  /// A PDF place names a page, not a section, so it has none.
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

  Map<String, dynamic> toJson() => {
    'parts': [
      for (final part in parts) [part.path, part.characters],
    ],
    'entries': [
      for (final entry in entries) [entry.title, entry.depth, entry.start],
    ],
  };
}

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
  // A stable sort, so that entries that start at one place keep their
  // order in the contents.
  final order = [for (var index = 0; index < entries.length; index++) index]
    ..sort((a, b) {
      final by = entries[a].start.compareTo(entries[b].start);
      return by != 0 ? by : a.compareTo(b);
    });
  return TextOutline(
    parts: parts,
    entries: [for (final index in order) entries[index]],
  );
}
