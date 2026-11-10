import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'book_crop.dart';
import 'pdf.dart';
import 'word_bands.dart';

/// The colors that the word view takes from the reader's theme.
class WordTint {
  const WordTint({
    required this.paper,
    required this.ink,
    required this.brightness,
  });

  /// The theme's paper and text colors.
  WordTint.of(ColorScheme scheme)
    : paper = scheme.surface,
      ink = scheme.onSurface,
      brightness = scheme.brightness;

  final Color paper;
  final Color ink;
  final Brightness brightness;
}

/// One band image of a shown screen and the sprites that draw its pieces.
class DrawnBand {
  DrawnBand({
    required this.image,
    required this.tint,
    required this.transforms,
    required this.rects,
    this.paperLightness = 1,
    this.inkLightness = 0,
  });

  /// The sprites of [band] of [bands], drawn from [image].
  factory DrawnBand.of(ui.Image image, WordBands bands, int band) {
    final first = bands.spriteStarts[band], end = bands.spriteStarts[band + 1];
    return DrawnBand(
      image: image,
      tint: bands.tint(band),
      transforms: Float32List.sublistView(bands.transforms, first * 4, end * 4),
      rects: Float32List.sublistView(bands.rects, first * 4, end * 4),
      paperLightness: bands.paperLightness,
      inkLightness: bands.inkLightness,
    );
  }

  final ui.Image image;
  final BandTint tint;
  final Float32List transforms;
  final Float32List rects;

  /// The lightness of the page's paper and ink in [image], from 0 to 1.
  final double paperLightness;
  final double inkLightness;
}

/// Paints the paper of [tint] over [size], then each band of [bands] with
/// one [Canvas.drawRawAtlas] call, tinted on the GPU.
///
/// An ink band draws its pixels in the text color, with an opacity that
/// goes from 1 at the page's ink lightness to 0 at its paper lightness,
/// over the paper. So the ink of a scan draws in the text color and its
/// paper, which is darker than white, leaves the theme's paper. The paper
/// of a turned word, which overlaps its neighbor by a fraction of a pixel,
/// never paints over the neighbor's ink. A picture band keeps its colors:
/// on light paper they multiply by the paper, so white becomes the paper,
/// and on dark paper they show at 80 percent brightness and are not
/// inverted.
void paintScreen(
  Canvas canvas,
  Size size,
  List<DrawnBand> bands,
  WordTint tint,
) {
  canvas.drawRect(Offset.zero & size, Paint()..color = tint.paper);
  for (final band in bands) {
    canvas.drawRawAtlas(
      band.image,
      band.transforms,
      band.rects,
      null,
      null,
      null,
      Paint()
        // A level word lands on whole device pixels at one band pixel for
        // one device pixel, so bilinear sampling copies its pixels. A
        // turned word needs it to stay smooth.
        ..filterQuality = FilterQuality.low
        ..colorFilter = band.tint == BandTint.ink
            ? _inkFilter(tint, band)
            : _pictureFilter(tint),
    );
  }
}

/// The weights of red, green and blue in a pixel's lightness, as the page
/// analysis measures it (Rec. 601).
const _red = .299, _green = .587, _blue = .114;

/// The brightness of a picture on dark paper.
const _nightPicture = .8;

ColorFilter _inkFilter(WordTint tint, DrawnBand band) {
  // The opacity is (paper - lightness) / (paper - ink), on the 0 to 255
  // scale of the matrix. The GPU clamps it to 0 to 1.
  final range = band.paperLightness - band.inkLightness;
  return ColorFilter.matrix([
    ...[0, 0, 0, 0, tint.ink.r * 255],
    ...[0, 0, 0, 0, tint.ink.g * 255],
    ...[0, 0, 0, 0, tint.ink.b * 255],
    ...[
      -_red / range,
      -_green / range,
      -_blue / range,
      band.paperLightness / range,
    ],
    0,
  ]);
}

ColorFilter _pictureFilter(WordTint tint) {
  final (r, g, b) = tint.brightness == Brightness.light
      ? (tint.paper.r, tint.paper.g, tint.paper.b)
      : (_nightPicture, _nightPicture, _nightPicture);
  return ColorFilter.matrix([
    ...[r, 0, 0, 0, 0],
    ...[0, g, 0, 0, 0],
    ...[0, 0, b, 0, 0],
    ...[0, 0, 0, 1, 0],
  ]);
}

/// Shows the screen that [screen] holds, in the theme's tints, filling the
/// space that it gets. Place it at a whole device pixel, so that level
/// words keep their pixels. It shows only paper while [screen] holds no
/// screen.
class WordScreenView extends StatelessWidget {
  const WordScreenView({super.key, required this.screen});
  final ValueListenable<WordScreen?> screen;

  @override
  Widget build(BuildContext context) => SizedBox.expand(
    child: CustomPaint(
      painter: _WordScreenPainter(
        screen,
        WordTint.of(Theme.of(context).colorScheme),
      ),
    ),
  );
}

class _WordScreenPainter extends CustomPainter {
  _WordScreenPainter(this.screen, this.tint) : super(repaint: screen);
  final ValueListenable<WordScreen?> screen;
  final WordTint tint;

  @override
  void paint(Canvas canvas, Size size) =>
      paintScreen(canvas, size, screen.value?.bands ?? const [], tint);

  @override
  bool shouldRepaint(_WordScreenPainter old) =>
      old.screen != screen ||
      old.tint.paper != tint.paper ||
      old.tint.ink != tint.ink ||
      old.tint.brightness != tint.brightness;
}

/// One screen that [PdfWordPages] shows: screen [screen] of the column of
/// source page [page] for [settings], and its band images.
class WordScreen {
  WordScreen({
    required this.page,
    required this.settings,
    required this.screen,
    required this.column,
    required this.bands,
  });
  final int page;
  final WordSettings settings;
  final int screen;
  final WordColumn column;
  final List<DrawnBand> bands;
}

typedef _ColumnKey = ({int page, WordSettings settings, BookProfile? profile});
typedef _ScreenKey = ({
  int page,
  WordSettings settings,
  int screen,
  WordColumn column,
});

/// The band images of one screen while they render and after.
class _ScreenImages {
  _ScreenImages(this.key, PdfBook book) {
    ready = _render(book);
  }

  final _ScreenKey key;
  WordColumn get column => key.column;

  /// The drawn bands, or null when the screen was dropped before they
  /// arrived.
  late final Future<List<DrawnBand>?> ready;

  /// The band images, once they arrived and until the screen is dropped.
  List<ui.Image>? images;
  bool dropped = false;

  int get pixels =>
      images?.fold<int>(0, (sum, image) => sum + image.width * image.height) ??
      0;

  Future<List<DrawnBand>?> _render(PdfBook book) async {
    final bands = column.bands;
    final first = bands.screenStarts[key.screen];
    final end = bands.screenStarts[key.screen + 1];
    Object? failure;
    StackTrace? trace;
    // The bands render one after another on pdfium's worker. Each render
    // has a handler at once, so a failure is never unhandled.
    final rendered = await Future.wait([
      for (var band = first; band < end; band++)
        book
            .renderPart(
              key.page,
              bands.pixelsPerPageUnit(band),
              bands.area(band),
            )
            .then<ui.Image?>(
              (image) => image,
              onError: (Object error, StackTrace stack) {
                failure ??= error;
                trace ??= stack;
                return null;
              },
            ),
    ]);
    if (failure != null || dropped) {
      for (final image in rendered) {
        image?.dispose();
      }
      if (failure != null) Error.throwWithStackTrace(failure!, trace!);
      return null;
    }
    final images = [for (final image in rendered) image!];
    this.images = images;
    return [
      for (var band = first; band < end; band++)
        DrawnBand.of(images[band - first], bands, band),
    ];
  }

  void drop() {
    dropped = true;
    for (final image in images ?? const <ui.Image>[]) {
      image.dispose();
    }
    images = null;
  }
}

/// The word view's data source for one viewport: the columns of the pages
/// that it shows, and the band images of the shown screen and of the next
/// screen in the direction of the last turn.
///
/// Band images exist for at most two screens. A screen's bands hold at most
/// twice its device pixels (see [WordBands]), so the live images hold at
/// most 4 times the pixels of a screen: about 42 MB on a Pixel 8, at every
/// text size. The eviction rule:
/// - When [show] asks for a screen, the images of every screen except the
///   shown one and the asked one go.
/// - When the asked screen's bands are ready, it becomes the shown screen,
///   and the images of the screen shown before it go.
/// - Then the next screen in the direction of the turn renders ahead.
///
/// So a change of the page, the text size or the width keeps the shown
/// screen until the new one is ready, and no blank frame shows. The tints
/// are drawn on the GPU, so a change of theme renders nothing.
///
/// Invariants, which [checkInvariants] makes sure of:
/// - At most two screens have images or render: the shown screen, and the
///   asked screen or the screen ahead.
/// - [shown] draws the images of the shown screen, and no live image is
///   disposed.
/// - Each screen's images hold at most twice its device pixels.
class PdfWordPages {
  PdfWordPages(this.book);
  final PdfBook book;

  final _shown = ValueNotifier<WordScreen?>(null);

  /// The shown screen, which [WordScreenView] draws.
  ValueListenable<WordScreen?> get shown => _shown;

  /// The columns that were asked for last, the least recent first.
  final _columns = <_ColumnKey, Future<WordColumn?>>{};
  _ColumnKey? _selectedColumn;
  static const _keptColumns = 4;

  /// The screens with images or renders, at most two.
  final _screens = <_ScreenKey, _ScreenImages>{};

  /// The screen that [shown] draws.
  _ScreenImages? _displayed;

  /// The number of the last call of [show]. A call that a later call
  /// replaced changes nothing when its bands arrive.
  var _generation = 0;
  var _disposed = false;

  /// The column of source page [page] for [settings], and the bands of its
  /// screens, as [ReflowPage.wordColumn] gives them. Null when the page has
  /// no word geometry. The layout and the band plans run in one hop of the
  /// book. The selected column stays unchanged until the page or settings
  /// change. Other cached plans are reused only for the same book profile.
  Future<WordColumn?> column(int page, WordSettings settings) {
    final ratio = settings.devicePixelRatio;
    if (!(ratio > 0 && ratio.isFinite)) {
      throw ArgumentError.value(ratio, 'devicePixelRatio', 'must be positive');
    }
    final selected = _selectedColumn;
    final key = selected?.page == page && selected?.settings == settings
        ? selected!
        : (page: page, settings: settings, profile: book.survey.profile);
    _selectedColumn = key;
    final column = _columns.remove(key) ?? _plan(key);
    _columns[key] = column;
    if (_columns.length > _keptColumns) _columns.remove(_columns.keys.first);
    return column;
  }

  Future<WordColumn?> _plan(_ColumnKey key) async {
    try {
      final reflow = await book.reflowPage(key.page);
      if (reflow == null) return null;
      return await reflow.wordColumn(key.settings);
    } catch (_) {
      // A failed column is asked for again by the next call.
      _columns.remove(key);
      rethrow;
    }
  }

  /// Shows [screen] of the column of [page] for [settings] once its bands
  /// are ready, and then renders ahead the screen after it, or before it
  /// when not [forward]. It completes when both are ready, or when a later
  /// call replaces it. The page must have word geometry.
  Future<void> show(
    int page,
    WordSettings settings,
    int screen, {
    bool forward = true,
  }) async {
    if (_disposed) throw StateError('The word pages are disposed.');
    final generation = ++_generation;
    final column = await this.column(page, settings);
    if (generation != _generation || _disposed) return;
    if (column == null) {
      throw ArgumentError.value(page, 'page', 'has no word geometry');
    }
    RangeError.checkValueInInterval(
      screen,
      0,
      column.column.screenCount - 1,
      'screen',
    );
    final key = (
      page: page,
      settings: settings,
      screen: screen,
      column: column,
    );
    _keep({_displayed?.key, key});
    final asked = _screens[key] ??= _ScreenImages(key, book);
    final List<DrawnBand>? bands;
    try {
      bands = await _ready(asked);
    } on Exception {
      // A call that a later call replaced reports nothing.
      if (generation != _generation) return;
      rethrow;
    }
    if (generation != _generation || bands == null) return;
    _shown.value = WordScreen(
      page: page,
      settings: settings,
      screen: screen,
      column: column,
      bands: bands,
    );
    _displayed = asked;
    _keep({key});
    final next = screen + (forward ? 1 : -1);
    if (next < 0 || next >= column.column.screenCount) return;
    final aheadKey = (
      page: page,
      settings: settings,
      screen: next,
      column: column,
    );
    final ahead = _screens[aheadKey] ??= _ScreenImages(aheadKey, book);
    try {
      await _ready(ahead);
    } on Exception {
      // The screen ahead renders again when it is asked for.
    }
  }

  /// The bands of [screen]. A screen that fails to render is forgotten, so
  /// the next call renders it again.
  Future<List<DrawnBand>?> _ready(_ScreenImages screen) async {
    try {
      return await screen.ready;
    } catch (_) {
      if (identical(_screens[screen.key], screen)) _screens.remove(screen.key);
      rethrow;
    }
  }

  /// Drops the images of every screen whose key is not in [kept].
  void _keep(Set<_ScreenKey?> kept) {
    _screens.removeWhere((key, screen) {
      if (kept.contains(key)) return false;
      screen.drop();
      return true;
    });
  }

  /// The band images that are alive now.
  @visibleForTesting
  Iterable<ui.Image> get liveImages =>
      _screens.values.expand((screen) => screen.images ?? const []);

  /// Throws a [StateError] when an invariant of the class comment does not
  /// hold. It runs only on demand, from a test or a debug switch.
  void checkInvariants() {
    void require(bool holds, String rule) {
      if (!holds) throw StateError('Word pages: $rule.');
    }

    require(_screens.length <= 2, 'at most two screens have images');
    final displayed = _displayed;
    if (displayed != null && !_disposed) {
      require(
        identical(_screens[displayed.key], displayed),
        'the shown screen keeps its images',
      );
      final shown = _shown.value!;
      require(
        shown.bands.length == displayed.images!.length &&
            [
              for (var band = 0; band < shown.bands.length; band++)
                identical(shown.bands[band].image, displayed.images![band]),
            ].every((same) => same),
        'the shown screen draws its own images',
      );
    }
    for (final screen in _screens.values) {
      require(!screen.dropped, 'a kept screen is not dropped');
      require(
        screen.pixels <= 2 * screen.column.bands.screenPixels,
        'a screen\'s images hold at most twice its pixels',
      );
      if (kDebugMode) {
        for (final image in screen.images ?? const <ui.Image>[]) {
          require(!image.debugDisposed, 'a live image is not disposed');
        }
      }
    }
  }

  /// Disposes every band image. The pages show nothing more.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _keep(const {});
    _displayed = null;
    _shown.dispose();
  }
}
