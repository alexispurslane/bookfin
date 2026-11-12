// The registration of the book faces that a section needs (boo-3huo).
//
// It runs on the UI isolate, because Flutter registers fonts there. The
// conversion of each font file to the bytes that Flutter reads runs in a
// worker isolate (font_files.dart).
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'font_files.dart';

/// Registers books' faces with Flutter.
///
/// Flutter keeps a registered font for the whole process and cannot unload
/// it. So the record of what is registered is process-wide too: a section
/// or a book that opens again reuses its faces instead of registering
/// copies.
abstract final class BookFonts {
  /// Each face's registration, by the family that it registers under. A
  /// face is in it from the start of its load, so a second load of it
  /// waits for the first.
  static final _loads = <String, Future<void>>{};

  /// Registers each of [faces], a font file path with the family that it
  /// registers under, once, from the bytes that [bytes] gives for the path.
  /// A face without bytes or that fails to load is skipped: the characters
  /// that it would draw draw in the next font of their run's fallback list.
  /// When the future completes, every one of [faces] that can load is
  /// registered. It never fails.
  static Future<void> load(
    Map<String, String> faces,
    Future<Uint8List?> Function(String path) bytes,
  ) {
    if (faces.isEmpty) return Future.value();
    final waits = <Future<void>>[];
    final fresh = <(String, String)>[];
    for (final MapEntry(key: path, value: family) in faces.entries) {
      if (_loads[family] case final pending?) {
        waits.add(pending);
      } else {
        fresh.add((path, family));
      }
    }
    if (fresh.isNotEmpty) {
      final registration = _register(fresh, bytes);
      for (final (_, family) in fresh) {
        _loads[family] = registration;
      }
      waits.add(registration);
    }
    return Future.wait(waits);
  }

  /// Reads the file of every face of [faces], a path and a family each,
  /// with [bytes], converts the files in one worker isolate, then registers
  /// each font that converts under its family.
  static Future<void> _register(
    List<(String, String)> faces,
    Future<Uint8List?> Function(String path) bytes,
  ) async {
    final read = await Future.wait([
      for (final (path, _) in faces)
        bytes(path).then<Uint8List?>((file) => file, onError: (_) => null),
    ]);
    final fresh = [
      for (final (index, file) in read.indexed)
        if (file != null) (faces[index].$2, file),
    ];
    if (fresh.isEmpty) return;
    final files = [for (final (_, file) in fresh) file];
    final fonts = await Isolate.run(
      () => [for (final file in files) sfntOf(file)],
    );
    await Future.wait([
      for (final (index, (family, _)) in fresh.indexed)
        if (fonts[index] case final font?)
          ui
              .loadFontFromList(font, fontFamily: family)
              .then<void>((_) {}, onError: (_) {}),
    ]);
  }
}
