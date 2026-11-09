// The page turn gesture that every reader view shares: a horizontal swipe
// of a touch or a pen, a trackpad pan, or a horizontal scroll.
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Reports a page turn when the person swipes across [child], pans across
/// it on a trackpad, or scrolls across it.
///
/// It watches the pointers itself, as reader.js did, and takes part in no
/// gesture arena. So the gestures inside [child] keep working: a tap, a
/// vertical scroll, a pinch, a text selection drag. A swipe that ends while
/// [swipes] says no turns nothing, for example while the person selects
/// text or while a zoomed page pans. A second finger ends a swipe, so a
/// pinch never turns the page.
class PageSwipes extends StatefulWidget {
  const PageSwipes({
    super.key,
    required this.onTurn,
    required this.child,
    this.swipes,
  });

  /// Reports a turn to the next page (true) or the previous one.
  final ValueChanged<bool> onTurn;

  /// Whether a touch swipe that ends now turns the page. Null means always.
  final bool Function()? swipes;
  final Widget child;

  /// A swipe turns the page when it moves more than [swipeDistance] logical
  /// pixels across and less than [swipeSlant] up or down. These are
  /// reader.js's numbers.
  static const swipeDistance = 60.0;
  static const swipeSlant = 50.0;

  /// A trackpad pan or scroll turns the page once it moves [scrollDistance]
  /// logical pixels across, more than it moves up or down.
  static const scrollDistance = 80.0;

  @override
  State<PageSwipes> createState() => _PageSwipesState();
}

class _PageSwipesState extends State<PageSwipes> {
  /// The touch that may be a swipe: its pointer and where it went down, in
  /// global logical pixels. A second finger ends it.
  int? _swipePointer;
  Offset? _swipeStart;

  /// How far the trackpad gesture in progress moved, and whether it turned
  /// the page already.
  Offset _pan = Offset.zero;
  bool _panTurned = false;

  /// How far the scroll signals moved across since the last turn. A
  /// trackpad that sends signals instead of gestures has no gesture end.
  double _scrolled = 0;

  void _pointerDown(PointerDownEvent event) {
    if (!_touches(event.kind)) return;
    if (_swipePointer == null) {
      _swipePointer = event.pointer;
      _swipeStart = event.position;
    } else {
      _swipeEnded();
    }
  }

  void _pointerUp(PointerUpEvent event) {
    if (event.pointer != _swipePointer) return;
    final start = _swipeStart!;
    _swipeEnded();
    if (!(widget.swipes?.call() ?? true)) return;
    final move = event.position - start;
    if (move.dx.abs() > PageSwipes.swipeDistance &&
        move.dy.abs() < PageSwipes.swipeSlant) {
      widget.onTurn(move.dx < 0);
    }
  }

  void _swipeEnded() {
    _swipePointer = null;
    _swipeStart = null;
  }

  /// A mouse drag selects text and a trackpad scrolls, so only a touch or a
  /// pen swipes.
  static bool _touches(PointerDeviceKind kind) => switch (kind) {
    PointerDeviceKind.touch ||
    PointerDeviceKind.stylus ||
    PointerDeviceKind.invertedStylus ||
    PointerDeviceKind.unknown => true,
    PointerDeviceKind.mouse || PointerDeviceKind.trackpad => false,
  };

  void _panned(PointerPanZoomUpdateEvent event) {
    _pan = event.pan;
    if (_panTurned ||
        _pan.dx.abs() < PageSwipes.scrollDistance ||
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
      if (_scrolled.abs() < PageSwipes.scrollDistance) return;
      final forward = _scrolled > 0;
      _scrolled = 0;
      widget.onTurn(forward);
    });
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerSignal: _signal,
    onPointerPanZoomStart: (_) {
      _pan = Offset.zero;
      _panTurned = false;
    },
    onPointerPanZoomUpdate: _panned,
    onPointerDown: _pointerDown,
    onPointerUp: _pointerUp,
    onPointerCancel: (event) {
      if (event.pointer == _swipePointer) _swipeEnded();
    },
    child: widget.child,
  );
}
