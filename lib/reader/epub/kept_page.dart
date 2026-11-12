// The kept page: the drawn form of one laid page, which a reopen of its
// book draws before the book loads (boo-sy2d).
//
// dart:ui cannot write a Picture to a file, and a raster of a page takes
// 100 KB or more at a phone's pixel density. So a kept page holds what
// drawPage reads of the page: each paragraph's recipe (the calls that built
// it: its text, its run styles and its placeholders) and the width that it
// was laid out at, where each piece and decoration sits, and the page's
// settings. Flutter's text engine breaks the lines of a paragraph built
// again from the same calls at the same width in the same places, with the
// same fonts, so drawPage draws the same pixels. The key of a kept file
// (kept_pages.dart) names the text engine and the fonts' install, and
// KeptPage.encode refuses a page that draws with a font of the book, which
// a new process has not registered when the book has not loaded yet.
import 'dart:convert';
import 'dart:ui' as ui;

import 'css.dart';
import 'layout.dart';
import 'paint.dart';
import 'prepare.dart';

/// One laid page, kept as the inputs of its drawing.
///
/// It holds the paragraphs that it built, and its [picture], until
/// [dispose].
final class KeptPage implements PageDrawing {
  KeptPage._(
    this.encoded,
    this.settings,
    this.height,
    this.pieces,
    this.decorations,
    this._paragraphs,
  );

  /// The format of [encode]'s text. A change of what layout or drawPage
  /// draws from the same inputs needs a new format, so that older kept
  /// pages decode to nothing.
  static const format = 1;

  /// The families that a kept page can draw with: the fonts that the app
  /// bundles or the platform has, which every process has before a book
  /// loads.
  static const _families = {readerFontFamily, 'monospace'};

  /// The kept form of [page], text of a few kilobytes that [decode] reads,
  /// or null when [page] draws with a font of its book, or shows a
  /// paragraph that no layout run built ([recipeOf]).
  ///
  /// It runs on the UI isolate, where the page's paragraphs live. It
  /// walks the pieces of one page and encodes a few kilobytes of JSON,
  /// about a tenth of a millisecond, less than a hop to a worker.
  static String? encode(LaidPage page) {
    try {
      return _encode(page);
    } on _Unkept {
      return null;
    }
  }

  static String? _encode(LaidPage page) {
    final styles = page.styles;
    final used = <int, int>{};
    final table = <RunStyle>[];
    int styleOf(int index) => used[index] ??= () {
      table.add(styles[index]);
      return table.length - 1;
    }();
    Map<String, Object?> paragraph(ui.Paragraph paragraph) {
      final recipe = recipeOf(paragraph) ?? (throw const _Unkept());
      final block = recipe.block;
      return {
        'width': paragraph.width.isFinite ? paragraph.width : null,
        'block': block == null ? null : [styleOf(block.$1), block.$2.index],
        'calls': [
          for (final call in recipe.calls)
            switch (call) {
              final int style => styleOf(style),
              (:final width, :final height, :final baselineOffset) => [
                width,
                height,
                baselineOffset,
              ],
              _ => call,
            },
        ],
      };
    }

    List<double> box(ui.Rect rect) => [
      rect.left,
      rect.top,
      rect.right,
      rect.bottom,
    ];
    Map<String, Object> image(DrawnImage image) => {
      'path': image.path,
      'invert': image.invert,
      'alt': image.alt,
    };
    // Everything is kept from the page's top, as drawPage draws it, so a
    // page that another run cut at another place on its strip keeps the
    // same form.
    final up = ui.Offset(0, -page.top);
    final body = {
      'format': format,
      'settings': page.settings.toJson(),
      'height': page.height,
      'pieces': [
        for (final piece in page.pieces)
          {
            'x': piece.x,
            'y': piece.y - page.top,
            'tops': piece.tops,
            'shifts': piece.shifts,
            'shown': piece.shown.isFinite ? piece.shown : null,
            'paragraph': paragraph(piece.paragraph),
            'inlines': [
              for (final (inline, held) in piece.inlines)
                [
                  ...box(inline),
                  switch (held) {
                    final ui.Paragraph raised => paragraph(raised),
                    final DrawnImage drawn => {'image': image(drawn)},
                    _ => throw const _Unkept(),
                  },
                ],
            ],
          },
      ],
      'decorations': [
        for (final decoration in page.decorations)
          switch (decoration) {
            RuleDecoration(:final rect) => ['rule', ...box(rect.shift(up))],
            ImageDecoration(:final rect, image: final drawn) => [
              'image',
              ...box(rect.shift(up)),
              image(drawn),
            ],
            MarkerDecoration(:final piece) => [
              'marker',
              piece.x,
              piece.y - page.top,
              paragraph(piece.paragraph),
            ],
          },
      ],
    };
    // The run styles are known once every paragraph named its own.
    if (table.any((style) => !_families.contains(style.family))) return null;
    return jsonEncode({
      ...body,
      'styles': [for (final style in table) _style(style)],
    });
  }

  /// The page that [kept], a text that [encode] wrote, holds, with its
  /// paragraphs built, or null when [kept] is not such a text.
  ///
  /// It runs on the UI isolate, where paragraphs are built: a few
  /// kilobytes of JSON decode in about a tenth of a millisecond, less than
  /// a hop to a worker, and the paragraphs of one page build and lay out in
  /// about as long as the page's own layout.
  static KeptPage? decode(String kept) {
    final built = <ui.Paragraph>[];
    try {
      final json = jsonDecode(kept);
      if (json is! Map || json['format'] != format) return null;
      final settings = PageSettings.fromJson(json['settings']);
      final styles = [
        for (final style in json['styles'] as List) _runStyle(style as List),
      ];
      if (styles.any((style) => !_families.contains(style.family))) {
        return null;
      }
      final textStyles = [
        for (final style in styles) runTextStyle(style, settings.ink),
      ];
      ui.Paragraph paragraph(Map<String, Object?> json) {
        final block = json['block'] as List?;
        final builder = ui.ParagraphBuilder(
          block == null
              ? ui.ParagraphStyle()
              : blockParagraphStyle(
                  styles[block[0] as int],
                  Align.values[block[1] as int],
                ),
        );
        for (final call in json['calls'] as List) {
          switch (call) {
            case final int style:
              builder.pushStyle(textStyles[style]);
            case final String text:
              builder.addText(text);
            case null:
              builder.pop();
            case [final num width, final num height, final num offset]:
              builder.addPlaceholder(
                width.toDouble(),
                height.toDouble(),
                ui.PlaceholderAlignment.baseline,
                baseline: ui.TextBaseline.alphabetic,
                baselineOffset: offset.toDouble(),
              );
            default:
              throw FormatException('Not a paragraph call: $call');
          }
        }
        final width = json['width'] as num?;
        final paragraph = builder.build();
        built.add(paragraph);
        return paragraph..layout(
          ui.ParagraphConstraints(width: width?.toDouble() ?? double.infinity),
        );
      }

      ui.Rect rect(List<Object?> json, [int at = 0]) => ui.Rect.fromLTRB(
        (json[at] as num).toDouble(),
        (json[at + 1] as num).toDouble(),
        (json[at + 2] as num).toDouble(),
        (json[at + 3] as num).toDouble(),
      );
      DrawnImage image(Map<String, Object?> json) => DrawnImage(
        json['path'] as String,
        invert: (json['invert'] as num).toDouble(),
        alt: json['alt'] as String,
      );
      List<double> numbers(Object? json) => [
        for (final value in json as List) (value as num).toDouble(),
      ];
      final pieces = [
        for (final piece in json['pieces'] as List)
          if (piece case final Map<String, Object?> piece)
            Piece.kept(
              paragraph(piece['paragraph'] as Map<String, Object?>),
              (piece['x'] as num).toDouble(),
              (piece['y'] as num).toDouble(),
              tops: numbers(piece['tops']),
              shifts: numbers(piece['shifts']),
              shown: (piece['shown'] as num?)?.toDouble() ?? double.infinity,
              inlines: [
                for (final inline in piece['inlines'] as List)
                  if (inline case [...final _, final Map<String, Object?> held])
                    (
                      rect(inline),
                      switch (held) {
                        {'image': final Map<String, Object?> drawn} => image(
                          drawn,
                        ),
                        _ => paragraph(held),
                      },
                    )
                  else
                    throw const FormatException('Not a kept inline.'),
              ],
            )
          else
            throw const FormatException('Not a kept piece.'),
      ];
      final decorations = <Decoration>[
        for (final decoration in json['decorations'] as List)
          switch (decoration) {
            ['rule', ...] => RuleDecoration(rect(decoration, 1)),
            ['image', ..., final Map<String, Object?> drawn] => ImageDecoration(
              rect(decoration, 1),
              image(drawn),
            ),
            [
              'marker',
              final num x,
              final num y,
              final Map<String, Object?> marker,
            ] =>
              MarkerDecoration(
                Piece.kept(
                  paragraph(marker),
                  x.toDouble(),
                  y.toDouble(),
                  tops: const [],
                  shifts: const [],
                  shown: double.infinity,
                  inlines: const [],
                ),
              ),
            _ => throw const FormatException('Not a kept decoration.'),
          },
      ];
      return KeptPage._(
        kept,
        settings,
        (json['height'] as num).toDouble(),
        pieces,
        decorations,
        built,
      );
    } on Object catch (error) {
      // A kept page is derived data: one that does not decode, whatever the
      // damage, draws nothing, and the next shown page replaces it.
      if (error is! FormatException &&
          error is! TypeError &&
          error is! ArgumentError &&
          error is! RangeError &&
          error is! StateError) {
        rethrow;
      }
      for (final paragraph in built) {
        paragraph.dispose();
      }
      return null;
    }
  }

  /// The text that [encode] wrote and [decode] read.
  final String encoded;

  @override
  final PageSettings settings;

  /// A kept page keeps everything from its top.
  @override
  double get top => 0;
  @override
  final double height;
  @override
  final List<Piece> pieces;
  @override
  final List<Decoration> decorations;
  final List<ui.Paragraph> _paragraphs;
  ui.Picture? _picture;
  bool _disposed = false;

  /// The page's picture: drawPage's picture of the page that it keeps,
  /// with an outline for each image, as the page's first picture draws
  /// images that are not decoded yet. Null once the page is disposed.
  ui.Picture? get picture =>
      _disposed ? null : _picture ??= drawPage(this, const {});

  /// Whether [page] is the page that this one keeps: the same settings, and
  /// the same paragraphs at the same places. It compares the kept text, so
  /// it works after [dispose] too.
  bool depicts(LaidPage page) => encode(page) == encoded;

  /// Lets go of the paragraphs and the picture. A second call does nothing.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _picture?.dispose();
    for (final paragraph in _paragraphs) {
      paragraph.dispose();
    }
  }

  static List<Object?> _style(RunStyle style) => [
    style.family,
    style.size,
    style.weight,
    style.italic,
    style.letterSpacing,
    style.wordSpacing,
    style.lineHeight,
    style.underline,
    style.lineThrough,
    style.smallCaps,
    style.oldstyleFigures,
  ];

  static RunStyle _runStyle(List<Object?> json) => switch (json) {
    [
      final String family,
      final num size,
      final int weight,
      final bool italic,
      final num letterSpacing,
      final num wordSpacing,
      final num? lineHeight,
      final bool underline,
      final bool lineThrough,
      final bool smallCaps,
      final bool oldstyleFigures,
    ] =>
      RunStyle(
        family: family,
        size: size.toDouble(),
        weight: weight,
        italic: italic,
        letterSpacing: letterSpacing.toDouble(),
        wordSpacing: wordSpacing.toDouble(),
        lineHeight: lineHeight?.toDouble(),
        underline: underline,
        lineThrough: lineThrough,
        smallCaps: smallCaps,
        oldstyleFigures: oldstyleFigures,
      ),
    _ => throw const FormatException('Not a kept run style.'),
  };
}

/// A page that [KeptPage.encode] cannot keep.
final class _Unkept implements Exception {
  const _Unkept();
}
