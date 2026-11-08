// The native EPUB viewport: a leaf widget that draws the pager's shown page
// and reports what the person did.
//
// It causes one effect of its own: from its layout, it presents the page
// settings to the pager, which is a request for pages, like an Image that
// resolves its image. Every other action goes up through a callback: a tap,
// a link, a page turn and, later, a copy. A render object subscribes to the
// shown page, so a new page repaints the viewport without a rebuild.
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'layout.dart';
import 'pager.dart';
import 'prepare.dart';

/// Draws what [pager] shows and reports taps, links, page turns and copies.
///
/// It fills the space that its parent gives it, which must be bounded. It
/// presents that size, [fontSize] and [night] to [pager] whenever one of
/// them changes, and keeps the last page painted until the pager shows the
/// page for the new settings.
class EpubViewport extends StatefulWidget {
  const EpubViewport({
    super.key,
    required this.pager,
    required this.fontSize,
    required this.night,
    required this.onTap,
    required this.onTurn,
    required this.onLink,
    required this.onCopy,
  });
  final EpubPager pager;

  /// The text size in pixels, after the system text scale.
  final double fontSize;
  final bool night;

  /// A tap that hit no link and ended no selection.
  final VoidCallback onTap;

  /// A swipe, key or trackpad scroll that asks for the next page (true) or
  /// the previous one.
  final ValueChanged<bool> onTurn;

  /// A tap on an internal link, with its destination for `contents`,
  /// relative to the package document's directory.
  final ValueChanged<String> onLink;

  /// The person chose Copy for the selected text.
  final ValueChanged<String> onCopy;

  /// A swipe turns the page when it moves more than [swipeDistance] logical
  /// pixels across and less than [swipeSlant] up or down. These are
  /// reader.js's numbers.
  static const swipeDistance = 60.0;
  static const swipeSlant = 50.0;

  /// A trackpad scroll turns the page once it moves [scrollDistance]
  /// logical pixels across, more than it moves up or down.
  static const scrollDistance = 80.0;

  @override
  State<EpubViewport> createState() => _EpubViewportState();
}

class _EpubViewportState extends State<EpubViewport> {
  final _focus = FocusNode(debugLabel: 'EPUB page');

  /// Where the touch of the drag in progress went down and where it is
  /// now, in logical pixels from the page's top left corner.
  Offset? _dragStart;
  Offset? _dragEnd;

  /// How far the trackpad gesture in progress moved, and whether it turned
  /// the page already.
  Offset _pan = Offset.zero;
  bool _panTurned = false;

  /// How far the scroll signals moved across since the last turn. A
  /// trackpad that sends signals instead of gestures has no gesture end.
  double _scrolled = 0;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _tap(TapUpDetails details) {
    _focus.requestFocus();
    final link = widget.pager.linkAt(details.localPosition);
    if (link != null) {
      widget.onLink(link);
    } else {
      widget.onTap();
    }
  }

  void _dragDown(DragDownDetails details) =>
      _dragStart = _dragEnd = details.localPosition;

  void _dragMoved(DragUpdateDetails details) =>
      _dragEnd = details.localPosition;

  void _dragCancelled() => _dragStart = _dragEnd = null;

  void _dragEnded(DragEndDetails _) {
    final start = _dragStart;
    final end = _dragEnd;
    _dragCancelled();
    if (start == null || end == null) return;
    final move = end - start;
    if (move.dx.abs() > EpubViewport.swipeDistance &&
        move.dy.abs() < EpubViewport.swipeSlant) {
      widget.onTurn(move.dx < 0);
    }
  }

  void _panned(PointerPanZoomUpdateEvent event) {
    _pan = event.pan;
    if (_panTurned ||
        _pan.dx.abs() < EpubViewport.scrollDistance ||
        _pan.dx.abs() <= _pan.dy.abs()) {
      return;
    }
    _panTurned = true;
    // The fingers move left to scroll the page to the right.
    widget.onTurn(_pan.dx < 0);
  }

  void _signal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final delta = event.scrollDelta;
    if (delta.dx.abs() <= delta.dy.abs()) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      // A scroll the other way starts again from nothing.
      if (_scrolled != 0 && _scrolled.sign != delta.dx.sign) _scrolled = 0;
      _scrolled += delta.dx;
      if (_scrolled.abs() < EpubViewport.scrollDistance) return;
      final forward = _scrolled > 0;
      _scrolled = 0;
      widget.onTurn(forward);
    });
  }

  KeyEventResult _key(FocusNode _, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final forward = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowRight ||
      LogicalKeyboardKey.pageDown ||
      LogicalKeyboardKey.space => true,
      LogicalKeyboardKey.arrowLeft || LogicalKeyboardKey.pageUp => false,
      _ => null,
    };
    if (forward == null) return KeyEventResult.ignored;
    widget.onTurn(forward);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _focus,
    autofocus: true,
    onKeyEvent: _key,
    child: Listener(
      onPointerSignal: _signal,
      onPointerPanZoomStart: (_) {
        _pan = Offset.zero;
        _panTurned = false;
      },
      onPointerPanZoomUpdate: _panned,
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: {
          TapGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                () => TapGestureRecognizer(debugOwner: this),
                (tap) => tap.onTapUp = _tap,
              ),
          // A mouse drag selects text and a trackpad scrolls, so only a
          // touch or a pen swipes.
          PanGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<PanGestureRecognizer>(
                () => PanGestureRecognizer(
                  debugOwner: this,
                  supportedDevices: const {
                    PointerDeviceKind.touch,
                    PointerDeviceKind.stylus,
                    PointerDeviceKind.invertedStylus,
                    PointerDeviceKind.unknown,
                  },
                ),
                (pan) => pan
                  ..dragStartBehavior = DragStartBehavior.down
                  ..onDown = _dragDown
                  ..onUpdate = _dragMoved
                  ..onEnd = _dragEnded
                  ..onCancel = _dragCancelled,
              ),
        },
        child: _Page(
          pager: widget.pager,
          fontSize: widget.fontSize,
          night: widget.night,
        ),
      ),
    ),
  );
}

/// The page itself: it paints the shown picture and presents its size.
class _Page extends LeafRenderObjectWidget {
  const _Page({
    required this.pager,
    required this.fontSize,
    required this.night,
  });
  final EpubPager pager;
  final double fontSize;
  final bool night;

  @override
  _RenderPage createRenderObject(BuildContext context) =>
      _RenderPage(pager, fontSize, night);

  @override
  void updateRenderObject(BuildContext context, _RenderPage page) => page
    ..pager = pager
    ..fontSize = fontSize
    ..night = night;
}

/// Paints the pager's shown picture at logical size, over the paper of the
/// current theme. Before the first page, it paints the paper only.
///
/// It listens to the shown page while it is attached, so that a new page
/// repaints it alone. Its layout presents the page settings whenever they
/// differ from the ones that it presented last.
class _RenderPage extends RenderBox {
  _RenderPage(this._pager, this._fontSize, this._night);

  EpubPager _pager;
  set pager(EpubPager value) {
    if (identical(value, _pager)) return;
    if (attached) _pager.shown.removeListener(markNeedsPaint);
    _pager = value;
    if (attached) _pager.shown.addListener(markNeedsPaint);
    _presented = null;
    markNeedsLayout();
  }

  double _fontSize;
  set fontSize(double value) {
    if (value == _fontSize) return;
    _fontSize = value;
    markNeedsLayout();
  }

  bool _night;
  set night(bool value) {
    if (value == _night) return;
    _night = value;
    markNeedsLayout();
    markNeedsPaint();
  }

  /// The settings that the page presented last, or null before it did.
  PageSettings? _presented;

  @override
  bool get isRepaintBoundary => true;

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  /// The settings of the page as it is laid out now.
  PageSettings get _settings => PageSettings(
    width: size.width,
    height: size.height,
    fontSize: _fontSize,
    night: _night,
  );

  @override
  void performLayout() {
    final settings = _settings;
    // The pager takes only a page area and a text size. A zero size, such as
    // a collapsed parent's, waits for a real one.
    bool positive(double value) => value > 0 && value.isFinite;
    if (settings == _presented ||
        !positive(settings.width) ||
        !positive(settings.height) ||
        !positive(settings.fontSize)) {
      return;
    }
    _presented = settings;
    // The pager notifies later, never during the call, so nothing changes
    // during layout.
    _pager.present(settings);
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _pager.shown.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _pager.shown.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    final area = offset & size;
    canvas.drawRect(area, Paint()..color = _settings.paper);
    final shown = _pager.shown.value;
    if (shown == null) return;
    canvas
      ..save()
      ..clipRect(area)
      ..translate(offset.dx, offset.dy)
      ..drawPicture(shown.picture)
      ..restore();
  }
}
