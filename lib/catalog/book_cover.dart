import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'covers.dart';
import 'jellyfin.dart';
import 'model.dart';

/// The parts of a [CoverScope] that a widget can depend on alone.
enum CoverAspect {
  /// The cover store and the signed-in account, which covers read.
  covers,

  /// The book open in the player, which glass panes read.
  playing,
}

/// Gives every cover below it the cover store and the signed-in account, and
/// every glass pane below it the book open in the player. A widget that
/// depends on one [CoverAspect] rebuilds only when that part changes.
class CoverScope extends InheritedModel<CoverAspect> implements InheritedTheme {
  const CoverScope({
    super.key,
    required this.covers,
    required this.session,
    this.playing,
    required super.child,
  });
  final Covers? covers;
  final JellyfinSession? session;

  /// The book open in the player, if any.
  final Book? playing;

  /// The scope above [context]. [context] rebuilds when [aspect] changes, or
  /// when any part changes without an [aspect].
  static CoverScope? of(BuildContext context, [CoverAspect? aspect]) =>
      InheritedModel.inheritFrom<CoverScope>(context, aspect: aspect);

  /// Sheets, dialogs and menus copy the scope, so covers show in them too.
  @override
  Widget wrap(BuildContext context, Widget child) => CoverScope(
    covers: covers,
    session: session,
    playing: playing,
    child: child,
  );

  bool _coversChanged(CoverScope old) =>
      old.covers != covers ||
      old.session?.scope.key != session?.scope.key ||
      old.session?.credentialIdentity != session?.credentialIdentity;

  @override
  bool updateShouldNotify(CoverScope oldWidget) =>
      _coversChanged(oldWidget) || oldWidget.playing != playing;

  @override
  bool updateShouldNotifyDependent(
    CoverScope oldWidget,
    Set<CoverAspect> dependencies,
  ) =>
      (dependencies.contains(CoverAspect.covers) &&
          _coversChanged(oldWidget)) ||
      (dependencies.contains(CoverAspect.playing) &&
          oldWidget.playing != playing);
}

/// How wide a cover image is decoded. Each class has its own place in the
/// image cache, so a cover in a list row holds a small image, not one sized
/// for a stage.
enum CoverSize {
  /// For blurred covers, where only the colors remain.
  tiny(64),

  /// For list rows.
  small(224),

  /// For compact grid tiles.
  medium(360),

  /// For stages and spacious grid tiles.
  large(540);

  const CoverSize(this.width);

  /// The widest that a cover of this class is decoded, in image pixels.
  final int width;

  /// The smallest class that is at least [pixels] wide, else the largest.
  static CoverSize fitting(double pixels) => values.firstWhere(
    (size) => size.width >= pixels,
    orElse: () => CoverSize.large,
  );
}

/// A cover image that Flutter's image cache keys by account, image version
/// and size class. A replacement credential retries failed images, while
/// policy validation of the same credential retains the image-cache key.
class CoverImage extends ImageProvider<CoverImage> {
  const CoverImage(this.covers, this.session, this.cover, this.size);
  final Covers covers;
  final JellyfinSession session;
  final CoverRef cover;
  final CoverSize size;

  @override
  Future<CoverImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(CoverImage key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(_load(decode));

  Future<ImageInfo> _load(ImageDecoderCallback decode) async {
    final bytes = await covers.load(session, cover);
    if (bytes == null) throw StateError('No cover image.');
    final codec = await decode(
      await ui.ImmutableBuffer.fromUint8List(bytes),
      getTargetSize: (width, height) =>
          ui.TargetImageSize(width: math.min(width, size.width)),
    );
    return ImageInfo(image: (await codec.getNextFrame()).image);
  }

  @override
  bool operator ==(Object other) =>
      other is CoverImage &&
      other.covers == covers &&
      other.session.scope.key == session.scope.key &&
      other.session.credentialIdentity == session.credentialIdentity &&
      other.cover == cover &&
      other.size == size;

  @override
  int get hashCode => Object.hash(
    covers,
    session.scope.key,
    session.credentialIdentity,
    cover,
    size,
  );
}

const _palettes = [
  [Color(0xFF4F6B5A), Color(0xFF2E3F35)],
  [Color(0xFFA8653A), Color(0xFF6B3B22)],
  [Color(0xFF3D4F73), Color(0xFF232D45)],
  [Color(0xFF8B6F9E), Color(0xFF4D3B5C)],
  [Color(0xFFC49A4B), Color(0xFF80602A)],
  [Color(0xFF7A3D3D), Color(0xFF472020)],
  [Color(0xFF5C7D8A), Color(0xFF2F4750)],
  [Color(0xFF6B5A45), Color(0xFF3D3226)],
];

/// The two colors of the generated cover of a title. The same title always
/// gets the same colors.
List<Color> coverPalette(String title) {
  var hash = 0;
  for (final unit in title.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return _palettes[hash % _palettes.length];
}

/// A book cover with a 2:3 shape. It shows the Jellyfin cover when one is
/// available, and a generated cover with the title otherwise.
class BookCover extends StatelessWidget {
  const BookCover({
    super.key,
    required this.title,
    this.author,
    this.cover,
    this.downloaded = false,
    this.stacked = false,
    this.label,
    this.showText = true,
  });

  BookCover.book(
    Book book, {
    Key? key,
    bool downloaded = false,
    bool showText = true,
  }) : this(
         key: key,
         title: book.title,
         author: book.author,
         cover: book.cover,
         downloaded: downloaded,
         showText: showText,
       );

  final String title;
  final String? author;
  final CoverRef? cover;

  /// Draws the checkmark in the upper right corner.
  final bool downloaded;

  /// Draws two sheets behind the cover, for a series.
  final bool stacked;

  /// A short note in the upper left corner, for example "4 books".
  final String? label;

  /// Writes the title on a generated cover. Small covers leave it out.
  final bool showText;

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 2 / 3,
    child: LayoutBuilder(
      builder: (context, size) {
        final width = size.maxWidth;
        final radius = BorderRadius.only(
          topLeft: Radius.circular(width * 0.03),
          bottomLeft: Radius.circular(width * 0.03),
          topRight: Radius.circular(width * 0.07),
          bottomRight: Radius.circular(width * 0.07),
        );
        final face = _CoverFace(
          title: title,
          author: author,
          cover: cover,
          size: CoverSize.fitting(
            width * MediaQuery.devicePixelRatioOf(context),
          ),
          radius: radius,
          showText: showText && width >= 56,
        );
        final night = Theme.of(context).brightness == Brightness.dark;
        final badge = width * 0.17 < 16 ? 16.0 : math.min(width * 0.17, 28.0);
        final inset = math.max(3.0, width * 0.04);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            if (stacked)
              for (final (step, shade) in [
                (2, night ? 0xFF4A3D31 : 0xFFD4C3A6),
                (1, night ? 0xFF56473A : 0xFFC7B496),
              ])
                Positioned.fill(
                  child: Transform.translate(
                    offset: Offset(step * width * 0.022, -step * width * 0.026),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Color(shade),
                        borderRadius: radius,
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x26392A1F),
                            blurRadius: 5,
                            offset: Offset(1, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            Positioned.fill(child: face),
            if (label != null)
              Positioned(
                left: inset,
                top: inset,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xB8251E19),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    label!,
                    style: const TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 10,
                      color: Color(0xFFFFF9EF),
                    ),
                  ),
                ),
              ),
            if (downloaded)
              Positioned(
                right: inset,
                top: inset,
                child: Semantics(
                  label: 'Downloaded',
                  child: Container(
                    width: badge,
                    height: badge,
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerLowest,
                      shape: BoxShape.circle,
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x4D000000),
                          blurRadius: 4,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.check_rounded,
                      size: badge * 0.66,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}

class _CoverFace extends StatelessWidget {
  const _CoverFace({
    required this.title,
    required this.author,
    required this.cover,
    required this.size,
    required this.radius,
    required this.showText,
  });
  final String title;
  final String? author;
  final CoverRef? cover;
  final CoverSize size;
  final BorderRadius radius;
  final bool showText;

  @override
  Widget build(BuildContext context) {
    final scope = CoverScope.of(context, CoverAspect.covers);
    final palette = coverPalette(title);
    final generated = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: palette,
        ),
      ),
      child: showText
          ? CustomPaint(
              painter: _CoverTextPainter(title: title, author: author),
              size: Size.infinite,
            )
          : null,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: const [
          BoxShadow(
            color: Color(0x2E392A1F),
            blurRadius: 8,
            offset: Offset(2, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            generated,
            if (scope?.covers != null &&
                scope?.session != null &&
                cover != null)
              Image(
                image: CoverImage(scope!.covers!, scope.session!, cover!, size),
                fit: BoxFit.cover,
                gaplessPlayback: true,
                excludeFromSemantics: true,
                frameBuilder: (context, child, frame, synchronous) =>
                    synchronous || frame != null
                    ? child
                    : const SizedBox.shrink(),
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            // The spine: a narrow shadow along the left edge.
            const Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: 3,
                height: double.infinity,
                child: ColoredBox(color: Color(0x1F000000)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Paints the title and author of a generated cover. The cover is decoration:
/// the title also appears as text next to it, so this text has no semantics.
class _CoverTextPainter extends CustomPainter {
  _CoverTextPainter({required this.title, required this.author});
  final String title;
  final String? author;

  static const _ink = Color(0xFFFFF9EF);

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..color = const Color(0x40FFF9EF);
    canvas.drawCircle(Offset(width * 1.05, width * 0.2), width * 0.6, ring);
    final left = width * 0.1;
    final textWidth = width - left - width * 0.08;
    final authorPainter = author?.isNotEmpty == true && width >= 100
        ? (TextPainter(
            text: TextSpan(
              text: author,
              style: TextStyle(
                fontFamily: 'Outfit',
                fontSize: width * 0.065,
                color: const Color(0xCCFFF9EF),
              ),
            ),
            maxLines: 1,
            ellipsis: '…',
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: textWidth))
        : null;
    final titlePainter = TextPainter(
      text: TextSpan(
        text: title,
        style: TextStyle(
          fontFamily: 'Source Serif 4',
          fontWeight: FontWeight.w600,
          fontSize: width * 0.11,
          height: 1.1,
          color: _ink,
        ),
      ),
      maxLines: 4,
      ellipsis: '…',
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: textWidth);
    var bottom = size.height - width * 0.1;
    if (authorPainter != null) {
      bottom -= authorPainter.height;
      authorPainter.paint(canvas, Offset(left, bottom));
      bottom -= width * 0.03;
      authorPainter.dispose();
    }
    titlePainter.paint(canvas, Offset(left, bottom - titlePainter.height));
    titlePainter.dispose();
  }

  @override
  bool shouldRepaint(_CoverTextPainter oldDelegate) =>
      oldDelegate.title != title || oldDelegate.author != author;
}

/// A book's cover blurred until only its colors remain, drawn at [opacity]
/// over what lies beneath. A book without a cover image uses its generated
/// palette.
///
/// The blur is drawn once, into a bitmap a few pixels per [sigma] across,
/// and stretched over the widget. Each frame then draws one small image
/// instead of blurring a screen-sized layer again.
class CoverBlur extends StatefulWidget {
  const CoverBlur({
    super.key,
    required this.book,
    this.sigma = 28,
    this.opacity = 1,
    this.mask,
  });
  final Book book;

  /// How far the blur spreads: the standard deviation of the Gaussian, in
  /// logical pixels.
  final double sigma;

  /// How much the blurred cover hides what lies beneath it, from 0 to 1.
  final double opacity;

  /// Shapes the blurred cover: each point keeps as much of it as the mask's
  /// alpha there. The mask spans the whole widget.
  final Gradient? mask;

  @override
  State<CoverBlur> createState() => _CoverBlurState();
}

class _CoverBlurState extends State<CoverBlur> {
  ImageStream? _stream;
  ImageInfo? _cover;
  late final _listener = ImageStreamListener(
    (cover, _) => setState(() {
      _cover?.dispose();
      _cover = cover;
    }),
    // Without its image, the blur shows the generated palette.
    onError: (_, _) {},
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(CoverBlur oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.book.cover != widget.book.cover) _resolve();
  }

  /// Listens for the tiny decode of the book's cover, the only size that a
  /// blur needs.
  void _resolve() {
    final scope = CoverScope.of(context, CoverAspect.covers);
    final cover = widget.book.cover;
    final stream =
        scope?.covers != null && scope?.session != null && cover != null
        ? CoverImage(
            scope!.covers!,
            scope.session!,
            cover,
            CoverSize.tiny,
          ).resolve(createLocalImageConfiguration(context))
        : null;
    if (stream?.key != null && stream?.key == _stream?.key) return;
    _stream?.removeListener(_listener);
    _cover?.dispose();
    _cover = null;
    _stream = stream?..addListener(_listener);
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    _cover?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _BlurredArt(
    cover: _cover?.image,
    palette: coverPalette(widget.book.title),
    sigma: widget.sigma,
    opacity: widget.opacity,
    mask: widget.mask,
  );
}

class _BlurredArt extends LeafRenderObjectWidget {
  const _BlurredArt({
    required this.cover,
    required this.palette,
    required this.sigma,
    required this.opacity,
    required this.mask,
  });
  final ui.Image? cover;
  final List<Color> palette;
  final double sigma;
  final double opacity;
  final Gradient? mask;

  @override
  _RenderBlurredArt createRenderObject(BuildContext context) =>
      _RenderBlurredArt()
        ..cover = cover
        ..palette = palette
        ..sigma = sigma
        ..opacity = opacity
        ..mask = mask;

  @override
  void updateRenderObject(BuildContext context, _RenderBlurredArt art) => art
    ..cover = cover
    ..palette = palette
    ..sigma = sigma
    ..opacity = opacity
    ..mask = mask;
}

/// Fills its box with the blurred art, drawn from a bitmap that it keeps
/// until the art or the box size changes.
class _RenderBlurredArt extends RenderBox {
  /// The blur's standard deviation in bitmap pixels. At six pixels per
  /// sigma, the stretched bitmap differs from a full-size blur by at most a
  /// few levels of 255.
  static const _bitmapSigma = 6.0;

  ui.Image? _cover;
  set cover(ui.Image? value) {
    if (value == _cover ||
        (value != null && _cover != null && value.isCloneOf(_cover!))) {
      return;
    }
    _cover = value;
    _forgetBitmap();
  }

  List<Color> _palette = const [];
  set palette(List<Color> value) {
    if (listEquals(value, _palette)) return;
    _palette = value;
    _forgetBitmap();
  }

  double _sigma = 1;
  set sigma(double value) {
    if (value == _sigma) return;
    _sigma = value;
    _forgetBitmap();
  }

  double _opacity = 1;
  set opacity(double value) {
    if (value == _opacity) return;
    _opacity = value;
    markNeedsPaint();
  }

  Gradient? _mask;
  set mask(Gradient? value) {
    if (value == _mask) return;
    _mask = value;
    _forgetBitmap();
  }

  ui.Image? _bitmap;

  /// The box size that [_bitmap] was drawn for.
  Size? _bitmapSize;

  void _forgetBitmap() {
    _bitmap?.dispose();
    _bitmap = null;
    markNeedsPaint();
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (size.isEmpty || _opacity == 0) return;
    if (_bitmapSize != size) {
      _bitmap?.dispose();
      _bitmap = null;
    }
    final bitmap = _bitmap ??= _drawBitmap();
    _bitmapSize = size;
    context.canvas.drawImageRect(
      bitmap,
      Offset.zero & Size(bitmap.width.toDouble(), bitmap.height.toDouble()),
      offset & size,
      Paint()
        ..filterQuality = FilterQuality.low
        ..color = Color.fromRGBO(0, 0, 0, _opacity),
    );
  }

  /// Draws the palette, the cover over it and the blur, then the mask, into a
  /// bitmap of the box's shape at [_bitmapSigma] pixels per sigma.
  ui.Image _drawBitmap() {
    final scale = _bitmapSigma / _sigma;
    final width = math.max(1, (size.width * scale).ceil());
    final height = math.max(1, (size.height * scale).ceil());
    final rect = Offset.zero & Size(width.toDouble(), height.toDouble());
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, rect)
      ..saveLayer(
        rect,
        Paint()
          ..imageFilter = ui.ImageFilter.blur(
            sigmaX: _bitmapSigma,
            sigmaY: _bitmapSigma,
          ),
      )
      ..drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: _palette,
          ).createShader(rect),
      );
    if (_cover case final cover?) {
      paintImage(
        canvas: canvas,
        rect: rect,
        image: cover,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
      );
    }
    canvas.restore();
    if (_mask case final mask?) {
      canvas.drawRect(
        rect,
        Paint()
          ..blendMode = BlendMode.dstIn
          ..shader = mask.createShader(rect),
      );
    }
    final picture = recorder.endRecording();
    final bitmap = picture.toImageSync(width, height);
    picture.dispose();
    return bitmap;
  }

  @override
  void dispose() {
    _bitmap?.dispose();
    super.dispose();
  }
}

/// The blurred cover behind a book's stage. By day it is a cover-colored wash
/// that fades into the page. At night it is a glow in the cover's colors
/// around the cover, on a dark stage.
class CoverBackdrop extends StatelessWidget {
  const CoverBackdrop({super.key, required this.book});
  final Book book;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = theme.colorScheme.surface;
    if (theme.brightness == Brightness.dark) {
      return Stack(
        fit: StackFit.expand,
        children: [
          CoverBlur(
            book: book,
            mask: const RadialGradient(
              center: Alignment(0, -0.15),
              radius: 0.8,
              colors: [Color(0xE6000000), Color(0x80000000), Color(0x00000000)],
              stops: [0, 0.5, 1],
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0, 0.6, 1],
                colors: [
                  surface.withValues(alpha: 0),
                  surface.withValues(alpha: 0),
                  surface,
                ],
              ),
            ),
          ),
        ],
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(bottom: 40, child: CoverBlur(book: book)),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0, 0.55, 0.86],
              colors: [
                surface.withValues(alpha: 0.3),
                surface.withValues(alpha: 0.55),
                surface,
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A book cover lit for a stage: a deep shadow by day, and a dark shadow
/// with a warm glow at night.
class StageCover extends StatelessWidget {
  const StageCover({
    super.key,
    required this.book,
    required this.width,
    this.downloaded = false,
  });
  final Book book;
  final double width;
  final bool downloaded;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: DecoratedBox(
      decoration: BoxDecoration(
        boxShadow: Theme.of(context).brightness == Brightness.dark
            ? const [
                BoxShadow(
                  color: Color(0x99000000),
                  blurRadius: 50,
                  offset: Offset(0, 20),
                ),
                BoxShadow(color: Color(0x59D68C52), blurRadius: 70),
              ]
            : const [
                BoxShadow(
                  color: Color(0x66392A1F),
                  blurRadius: 34,
                  offset: Offset(7, 16),
                ),
              ],
      ),
      child: BookCover.book(book, downloaded: downloaded),
    ),
  );
}
