// The benchmark of the trial renderer. It runs the same way under
// `flutter test` on the host and in the trial app on a phone
// (tool/epub_trial).
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'book.dart';
import 'layout.dart';
import 'paint.dart';

/// The measured cost of one section.
class SectionTiming {
  SectionTiming(this.index, this.characters, this.pages);
  final int index;

  /// The section's visible characters.
  final int characters;
  final int pages;

  /// Milliseconds to parse and style the section and to read its image
  /// sizes.
  double prepare = 0;

  /// Milliseconds to lay out the whole section and cut it into pages.
  double layout = 0;

  /// Milliseconds to record each drawn page into a picture, and to turn
  /// that picture into an image at the device's pixel ratio.
  final List<double> record = [];
  final List<double> raster = [];

  /// Milliseconds to decode the images of the drawn pages.
  double images = 0;

  Map<String, Object> toJson() => {
    'index': index,
    'characters': characters,
    'pages': pages,
    'prepareMs': _round(prepare),
    'layoutMs': _round(layout),
    'recordMs': [for (final value in record) _round(value)],
    'rasterMs': [for (final value in raster) _round(value)],
    'imagesMs': _round(images),
  };
}

/// The measured cost of a book.
class BookTiming {
  BookTiming(this.name);
  final String name;
  final sections = <SectionTiming>[];

  /// The resident memory of the process before the book and its largest
  /// value while each section is laid out, in bytes.
  int rssBefore = 0;
  int rssPeak = 0;

  Map<String, Object> toJson() {
    final drawn = [
      for (final section in sections)
        for (var page = 0; page < section.record.length; page++)
          section.record[page] + section.raster[page],
    ];
    final layouts = [
      for (final section in sections)
        if (section.characters > 2000) section.prepare + section.layout,
    ];
    return {
      'book': name,
      'sections': sections.length,
      'pages': sections.fold<int>(0, (total, section) => total + section.pages),
      'characters': sections.fold<int>(
        0,
        (total, section) => total + section.characters,
      ),
      'bookLayoutMs': _round(
        sections.fold<double>(
          0.0,
          (total, section) => total + section.prepare + section.layout,
        ),
      ),
      'chapterLayoutMedianMs': _round(_median(layouts)),
      'chapterLayoutMaxMs': _round(layouts.fold(0.0, math.max)),
      'pageDrawMedianMs': _round(_median(drawn)),
      'pageDrawMaxMs': _round(drawn.fold(0.0, math.max)),
      'rssBeforeMiB': _round(rssBefore / 1048576),
      'rssPeakMiB': _round(rssPeak / 1048576),
      'perSection': [for (final section in sections) section.toJson()],
    };
  }
}

double _round(double value) => (value * 100).round() / 100;

double _median(List<double> values) {
  if (values.isEmpty) return 0;
  final sorted = [...values]..sort();
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2;
}

/// Lays out every section of [book] for [theme] and draws its first,
/// middle and last pages at [pixelRatio] image pixels per layout pixel.
/// Only one section's layout is alive at a time, as in a reader.
Future<BookTiming> benchmarkBook(
  String name,
  TrialBook book,
  PageTheme theme, {
  double pixelRatio = 2.625,
}) async {
  final timing = BookTiming(name)..rssBefore = ProcessInfo.currentRss;
  timing.rssPeak = timing.rssBefore;
  final clock = Stopwatch();
  for (var index = 0; index < book.sections; index++) {
    clock
      ..reset()
      ..start();
    final prepared = await prepareSection(book.section(index), theme);
    final prepare = clock.elapsedMicroseconds / 1000;
    clock
      ..reset()
      ..start();
    final chapter = layoutSection(prepared, theme);
    final layout = clock.elapsedMicroseconds / 1000;
    final section =
        SectionTiming(index, prepared.dom.visibleLength, chapter.pages.length)
          ..prepare = prepare
          ..layout = layout;
    final drawn = {
      0,
      chapter.pages.length ~/ 2,
      chapter.pages.length - 1,
    }.toList()..sort();
    clock
      ..reset()
      ..start();
    final images = await decodeImages(chapter, drawn, scale: pixelRatio);
    section.images = clock.elapsedMicroseconds / 1000;
    for (final page in drawn) {
      clock
        ..reset()
        ..start();
      final picture = drawPage(chapter, page, images);
      section.record.add(clock.elapsedMicroseconds / 1000);
      clock
        ..reset()
        ..start();
      final image = await picture.toImage(
        (theme.width * pixelRatio).round(),
        (theme.height * pixelRatio).round(),
      );
      section.raster.add(clock.elapsedMicroseconds / 1000);
      image.dispose();
      picture.dispose();
    }
    for (final image in images.values) {
      image.dispose();
    }
    timing.rssPeak = math.max(timing.rssPeak, ProcessInfo.currentRss);
    timing.sections.add(section);
    _dispose(chapter);
  }
  return timing;
}

void _dispose(ChapterLayout chapter) {
  final seen = <ui.Paragraph>{};
  for (final slice in chapter.slices) {
    final paragraph = slice.piece?.paragraph;
    if (paragraph != null && seen.add(paragraph)) paragraph.dispose();
  }
}

/// The memory that laid-out sections keep: the growth of the process's
/// resident memory while the [count] longest sections of [book] stay laid
/// out at once, and the visible characters that they hold. The sections are
/// disposed afterwards.
Future<({int bytes, int characters, int sections})> retainedMemory(
  TrialBook book,
  PageTheme theme, {
  int count = 5,
}) async {
  final prepared = [
    for (var index = 0; index < book.sections; index++)
      await prepareSection(book.section(index), theme),
  ]..sort((a, b) => b.dom.visibleLength.compareTo(a.dom.visibleLength));
  final chosen = prepared.take(count).toList();
  final before = ProcessInfo.currentRss;
  final chapters = [
    for (final section in chosen) layoutSection(section, theme),
  ];
  final after = ProcessInfo.currentRss;
  chapters.forEach(_dispose);
  return (
    bytes: after - before,
    characters: chosen.fold<int>(
      0,
      (total, section) => total + section.dom.visibleLength,
    ),
    sections: chosen.length,
  );
}
