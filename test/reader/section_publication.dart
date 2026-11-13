import 'dart:collection';
import 'dart:typed_data';

import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/epub/publication.dart';

/// Uses a real admission's metadata with raw section bytes, so tests can
/// exercise malformed input that admission normally repairs or refuses.
class SectionPublication implements Publication {
  SectionPublication(this.source, this.textFiles, {List<String>? spine})
    : spine = spine ?? source.spine;

  final Publication source;
  @override
  final Map<String, Uint8List> textFiles;
  @override
  final List<String> spine;
  @override
  List<ContentsEntry> get contents => source.contents;
  @override
  String get packagePath => source.packagePath;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Counts reads of actual section bytes without replacing the parser.
class CountedSections extends MapBase<String, Uint8List> {
  CountedSections(this.source);
  final Map<String, Uint8List> source;
  final reads = <String, int>{};
  @override
  Uint8List? operator [](Object? key) {
    if (key is String) reads.update(key, (n) => n + 1, ifAbsent: () => 1);
    return source[key];
  }

  @override
  Iterable<String> get keys => source.keys;
  @override
  void operator []=(String key, Uint8List value) =>
      throw UnsupportedError('read only');
  @override
  void clear() => throw UnsupportedError('read only');
  @override
  Uint8List? remove(Object? key) => throw UnsupportedError('read only');
}
