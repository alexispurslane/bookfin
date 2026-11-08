import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'theme.dart';

/// A bar across one whole, such as an audio edition or a book, with a thumb
/// at the open place, a tick at each chapter start and a dot at each
/// bookmark. Every place on the bar is a fraction of the whole, from 0 at
/// its start to 1 at its end.
///
/// While the person drags, the bar shows the dragged place instead of
/// [value] and reports each place that the drag passes. On release it
/// reports where the drag ended, and it keeps that place until the future
/// that [onEnd] returns completes, so the thumb does not jump back while the
/// owner moves there.
class ScrubBar extends StatefulWidget {
  const ScrubBar({
    super.key,
    required this.value,
    required this.chapters,
    required this.bookmarks,
    required this.describe,
    required this.onEnd,
    this.onStart,
    this.onTarget,
    this.below,
  });

  /// The open place.
  final double value;

  /// The places where chapters start. A chapter at 0 or 1 has no tick.
  final List<double> chapters;

  /// The places of the bookmarks.
  final List<double> bookmarks;

  /// Names a place for assistive technology, such as "1:27:14".
  final String Function(double fraction) describe;

  /// Reports that a drag started, at the place where it started.
  final ValueChanged<double>? onStart;

  /// Reports each place that a drag passes, before it ends.
  final ValueChanged<double>? onTarget;

  /// Reports where a drag ended. The bar shows that place until the
  /// returned future completes.
  final Future<void> Function(double fraction) onEnd;

  /// Builds what shows under the bar. `target` is the dragged place while a
  /// drag or its move runs, and null otherwise.
  final Widget Function(BuildContext context, double? target)? below;

  @override
  State<ScrubBar> createState() => _ScrubBarState();
}

class _ScrubBarState extends State<ScrubBar> {
  /// The dragged place, while a drag or the move that it reported runs.
  double? _target;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = Theme.of(context).brightness == Brightness.dark
        ? theaterGlow
        : scheme.primary;
    final below = widget.below;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            activeTrackColor: scheme.primary,
            inactiveTrackColor: scheme.outlineVariant,
            thumbColor: scheme.primary,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Slider(
                padding: const EdgeInsets.symmetric(vertical: 12),
                semanticFormatterCallback: widget.describe,
                value: (_target ?? widget.value).clamp(0.0, 1.0),
                onChangeStart: (value) => widget.onStart?.call(value),
                onChanged: (value) {
                  setState(() => _target = value);
                  widget.onTarget?.call(value);
                },
                onChangeEnd: (value) async {
                  setState(() => _target = value);
                  await widget.onEnd(value);
                  if (mounted) setState(() => _target = null);
                },
              ),
              Positioned.fill(
                child: IgnorePointer(
                  // The marks change far less often than the thumb, so they
                  // keep a layer of their own.
                  child: RepaintBoundary(
                    child: CustomPaint(
                      key: const ValueKey('position marks'),
                      painter: _ScrubMarks(
                        chapters: widget.chapters,
                        bookmarks: widget.bookmarks,
                        chapterColor: scheme.surface,
                        bookmarkColor: accent,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (below != null) below(context, _target),
      ],
    );
  }
}

/// The chapter starts and the bookmarks, drawn across the bar where they
/// are along the whole.
class _ScrubMarks extends CustomPainter {
  _ScrubMarks({
    required this.chapters,
    required this.bookmarks,
    required this.chapterColor,
    required this.bookmarkColor,
  });
  final List<double> chapters;
  final List<double> bookmarks;
  final Color chapterColor;
  final Color bookmarkColor;

  /// The least distance between two chapter ticks, in logical pixels. Closer
  /// ticks would draw a solid band, so a tick that close to the last drawn
  /// one is left out.
  static const _tickSpacing = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final middle = size.height / 2;
    final chapter = Paint()..color = chapterColor;
    var last = double.negativeInfinity;
    for (final at in chapters) {
      final x = size.width * at;
      if (at > 0 && at < 1 && x - last >= _tickSpacing) {
        canvas.drawRect(Rect.fromLTWH(x - 0.75, middle - 5, 1.5, 10), chapter);
        last = x;
      }
    }
    final bookmark = Paint()..color = bookmarkColor;
    for (final at in bookmarks) {
      if (at >= 0 && at <= 1) {
        canvas.drawCircle(Offset(size.width * at, middle - 10), 3, bookmark);
      }
    }
  }

  @override
  bool shouldRepaint(_ScrubMarks old) =>
      !listEquals(chapters, old.chapters) ||
      !listEquals(bookmarks, old.bookmarks) ||
      chapterColor != old.chapterColor ||
      bookmarkColor != old.bookmarkColor;
}
