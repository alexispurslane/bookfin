import 'dart:convert';
import 'dart:typed_data';

import 'package:xml/xml_events.dart';

import 'document.dart';
import 'epub/publication.dart';

/// The contents that the reader lists for [publication]: its own, or, when
/// it has none, one "Chapter N" entry for each linear section of its spine,
/// as the WebView reader listed them (reader.js). Each href is relative to
/// the package document's directory, as contents hrefs are. It reads the
/// package document in the calling isolate.
List<ContentsEntry> listedContents(Publication publication) =>
    publication.contents.isNotEmpty
    ? publication.contents
    : spineContents(
        publication,
        linearSpine(publication.textFiles[publication.packagePath]!),
      );

/// One "Chapter N" entry for each section of the spine of [publication]
/// that [linear] marks as linear, in spine order.
List<ContentsEntry> spineContents(Publication publication, List<bool> linear) {
  final directory = publication.packagePath.split('/')..removeLast();
  String relative(String path) {
    final parts = path.split('/');
    var shared = 0;
    while (shared < directory.length &&
        shared < parts.length - 1 &&
        directory[shared] == parts[shared]) {
      shared++;
    }
    return [
      for (var up = shared; up < directory.length; up++) '..',
      ...parts.skip(shared).map(Uri.encodeComponent),
    ].join('/');
  }

  final sections = [
    for (final (index, path) in publication.spine.indexed)
      if (index < linear.length && linear[index]) path,
  ];
  return List.unmodifiable([
    for (final (index, path) in sections.indexed)
      ContentsEntry('Chapter ${index + 1}', relative(path)),
  ]);
}

/// Whether each spine item of the package document [package] is linear, in
/// spine order. As in epub.js, an item is linear unless its `linear`
/// attribute has a value other than `yes`.
List<bool> linearSpine(Uint8List package) => [
  for (final event in parseEvents(utf8.decode(package)))
    if (event case XmlStartElementEvent(
      localName: 'itemref',
      :final attributes,
    ))
      switch (attributes
          .where((attribute) => attribute.localName == 'linear')
          .firstOrNull
          ?.value) {
        null || '' || 'yes' => true,
        _ => false,
      },
];
