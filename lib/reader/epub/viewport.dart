// The native EPUB viewport: a leaf widget that draws the pager's shown page
// and reports what the person did.
//
// It causes one effect of its own: from its layout, it presents the page
// settings to the pager, which is a request for pages, like an Image that
// resolves its image. Every other action goes up through a callback: a tap,
// a link, a page turn and a copy. A render object subscribes to the shown
// page, so a new page repaints the viewport, updates its semantics and
// clears its selection without a rebuild.
//
// The page is the one selectable of a SelectionArea, which owns the
// selection gestures, the handles and the menu. Its Copy and the copy
// shortcut report the selected text through onCopy, and the screen writes
// the clipboard.
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'layout.dart';
import 'pager.dart';
import 'prepare.dart';
import 'selection.dart';
import 'semantics.dart';

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
  /// The page's key focus, which the selection region shares. Its keys turn
  /// pages before the region's shortcuts see them.
  late final _focus = FocusNode(debugLabel: 'EPUB page', onKeyEvent: _key);
  bool _autofocused = false;

  final _area = GlobalKey<SelectionAreaState>();
  final _page = GlobalKey();

  /// The selection on the shown page, which the page's render object owns.
  PageSelection? get _selection =>
      (_page.currentContext?.findRenderObject() as _RenderPage?)?.selection;

  /// The touch that may be a swipe: its pointer and where it went down, in
  /// global logical pixels. A second finger ends it.
  int? _swipePointer;
  Offset? _swipeStart;

  /// Whether text was selected when the tap in progress went down.
  bool _selectedAtDown = false;

  /// How far the trackpad gesture in progress moved, and whether it turned
  /// the page already.
  Offset _pan = Offset.zero;
  bool _panTurned = false;

  /// How far the scroll signals moved across since the last turn. A
  /// trackpad that sends signals instead of gestures has no gesture end.
  double _scrolled = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The page takes the key focus when it first shows, as Focus's
    // autofocus does.
    if (!_autofocused) {
      _autofocused = true;
      FocusScope.of(context).autofocus(_focus);
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  /// A tap at [point], in logical pixels from the page's top left corner,
  /// by a person or by a screen reader's action on a link. A tap on a link
  /// follows it. Any other tap clears the selection, or with none, calls
  /// onTap.
  void _tapAt(Offset point, {bool selected = false}) {
    _focus.requestFocus();
    final link = widget.pager.linkAt(point);
    if (link != null) {
      widget.onLink(link);
    } else if (selected) {
      _area.currentState?.selectableRegion.clearSelection();
    } else {
      widget.onTap();
    }
  }

  /// Copies the selected text, if any, through onCopy.
  void _copy() {
    if (_selection?.text case final text?) widget.onCopy(text);
  }

  /// A touch or a pen that goes down may start a swipe. It watches the
  /// pointer itself, as reader.js did, because the selection region claims
  /// horizontal drags.
  void _pointerDown(PointerDownEvent event) {
    if (!_swipes(event.kind)) return;
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
    // A drag with text selected adjusts the selection.
    if (_selection?.selecting ?? false) return;
    final move = event.position - start;
    if (move.dx.abs() > EpubViewport.swipeDistance &&
        move.dy.abs() < EpubViewport.swipeSlant) {
      widget.onTurn(move.dx < 0);
    }
  }

  void _swipeEnded() {
    _swipePointer = null;
    _swipeStart = null;
  }

  /// A mouse drag selects text and a trackpad scrolls, so only a touch or a
  /// pen swipes.
  static bool _swipes(PointerDeviceKind kind) => switch (kind) {
    PointerDeviceKind.touch ||
    PointerDeviceKind.stylus ||
    PointerDeviceKind.invertedStylus ||
    PointerDeviceKind.unknown => true,
    PointerDeviceKind.mouse || PointerDeviceKind.trackpad => false,
  };

  /// The selection menu: Copy, through onCopy, and Select all. On Android,
  /// Copy ends the selection, and elsewhere it hides the menu, as Flutter's
  /// own menu does.
  Widget _menu(BuildContext context, SelectableRegionState region) {
    void copied() {
      _copy();
      if (defaultTargetPlatform == TargetPlatform.android) {
        region.clearSelection();
      } else {
        region.hideToolbar();
      }
    }

    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: region.contextMenuAnchors,
      buttonItems: [
        for (final item in region.contextMenuButtonItems)
          if (item.type == ContextMenuButtonType.copy)
            item.copyWith(onPressed: copied)
          else if (item.type == ContextMenuButtonType.selectAll)
            item,
      ],
    );
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
  Widget build(BuildContext context) => Actions(
    // The copy shortcut reports the text through onCopy, and the region
    // writes no clipboard of its own.
    actions: {
      CopySelectionTextIntent: CallbackAction<CopySelectionTextIntent>(
        onInvoke: (_) => _copy(),
      ),
    },
    child: SelectionArea(
      key: _area,
      focusNode: _focus,
      contextMenuBuilder: _menu,
      child: Listener(
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
        child: RawGestureDetector(
          behavior: HitTestBehavior.opaque,
          // The page's own semantics turn pages and follow links. The
          // recognizer's default action would tap the page's corner.
          excludeFromSemantics: true,
          gestures: {
            TapGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                  () => TapGestureRecognizer(debugOwner: this),
                  (tap) => tap
                    ..onTapDown = ((_) =>
                        _selectedAtDown = _selection?.selecting ?? false)
                    ..onTapUp = (details) => _tapAt(
                      details.localPosition,
                      selected: _selectedAtDown,
                    ),
                ),
          },
          child: _Page(
            key: _page,
            pager: widget.pager,
            fontSize: widget.fontSize,
            night: widget.night,
            onTurn: widget.onTurn,
            onTapAt: _tapAt,
          ),
        ),
      ),
    ),
  );
}

/// The page itself: it paints the shown picture, presents its size, and
/// tells a screen reader what the page shows.
class _Page extends LeafRenderObjectWidget {
  const _Page({
    super.key,
    required this.pager,
    required this.fontSize,
    required this.night,
    required this.onTurn,
    required this.onTapAt,
  });
  final EpubPager pager;
  final double fontSize;
  final bool night;

  /// A screen reader's scroll action asks for a page.
  final ValueChanged<bool> onTurn;

  /// A screen reader's tap on a link taps it at this point of the page.
  final ValueChanged<Offset> onTapAt;

  @override
  _RenderPage createRenderObject(BuildContext context) =>
      _RenderPage(pager, fontSize, night, onTurn, onTapAt)
        ..registrar = SelectionContainer.maybeOf(context)
        ..selectionColor = _selectionColor(context);

  @override
  void updateRenderObject(BuildContext context, _RenderPage page) => page
    ..pager = pager
    ..fontSize = fontSize
    ..night = night
    ..onTurn = onTurn
    ..onTapAt = onTapAt
    ..registrar = SelectionContainer.maybeOf(context)
    ..selectionColor = _selectionColor(context);

  static Color _selectionColor(BuildContext context) =>
      DefaultSelectionStyle.of(context).selectionColor ??
      DefaultSelectionStyle.defaultColor;
}

/// Paints the pager's shown picture at logical size, over the paper of the
/// current theme. Before the first page, it paints the paper only.
///
/// It listens to the shown page while it is attached, so that a new page
/// repaints it and updates its semantics alone. Its layout presents the
/// page settings whenever they differ from the ones that it presented last.
///
/// Its semantics node is the page. Its scroll left action asks for the
/// next page and its scroll right action for the previous one, as a swipe
/// does. Its children are the shown page's text blocks and block images,
/// in reading order (see [pageBlocks]). A block of one span is one node. A
/// block of several, such as a paragraph with a link, holds a node for
/// each span. A link's tap action taps the page at the link.
///
/// It owns the [selection] of the shown page, which it paints over the
/// page in [selectionColor], with the selection handles' layers.
class _RenderPage extends RenderBox {
  _RenderPage(
    this._pager,
    this._fontSize,
    this._night,
    this.onTurn,
    this.onTapAt,
  ) {
    selection.page = _pager.shown.value?.page;
  }

  late final selection = PageSelection(this);

  set registrar(SelectionRegistrar? value) => selection.registrar = value;

  Color _selectionColor = DefaultSelectionStyle.defaultColor;
  set selectionColor(Color value) {
    if (value == _selectionColor) return;
    _selectionColor = value;
    markNeedsPaint();
  }

  EpubPager _pager;
  set pager(EpubPager value) {
    if (identical(value, _pager)) return;
    if (attached) _pager.shown.removeListener(_shownChanged);
    _pager = value;
    if (attached) _pager.shown.addListener(_shownChanged);
    _presented = null;
    markNeedsLayout();
    _shownChanged();
  }

  ValueChanged<bool> onTurn;
  ValueChanged<Offset> onTapAt;

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
    _pager.shown.addListener(_shownChanged);
  }

  @override
  void detach() {
    _pager.shown.removeListener(_shownChanged);
    super.detach();
  }

  @override
  void dispose() {
    selection.dispose();
    super.dispose();
  }

  void _shownChanged() {
    // The same page shows again once its images are decoded, and keeps its
    // selection.
    selection.page = _pager.shown.value?.page;
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  /// The page that [_blocks] read, and the nodes of its blocks. The pager
  /// shows a page twice when it has images, first without them, so the
  /// nodes stay the same for the same page, and a screen reader keeps its
  /// place.
  LaidPage? _read;
  List<SemanticsNode> _blocks = const [];

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config
      ..isSemanticBoundary = true
      ..onScrollLeft = (() => onTurn(true))
      ..onScrollRight = (() => onTurn(false));
  }

  @override
  void assembleSemanticsNode(
    SemanticsNode node,
    SemanticsConfiguration config,
    Iterable<SemanticsNode> children,
  ) {
    final page = _pager.shown.value?.page;
    if (!identical(page, _read)) {
      _read = page;
      _blocks = page == null ? const [] : _nodes(pageBlocks(page));
    }
    node.updateWith(config: config, childrenInInversePaintOrder: _blocks);
  }

  @override
  void clearSemantics() {
    super.clearSemantics();
    _read = null;
    _blocks = const [];
  }

  /// A node for each of [blocks], in their order.
  List<SemanticsNode> _nodes(List<PageBlock> blocks) {
    final area = Offset.zero & size;
    SemanticsNode node(
      Rect rect,
      int index,
      SemanticsConfiguration config, [
      List<SemanticsNode> children = const [],
    ]) => SemanticsNode()
      ..rect = rect.intersect(area)
      ..updateWith(
        config: config..sortKey = OrdinalSortKey(index.toDouble()),
        childrenInInversePaintOrder: children,
      );
    SemanticsConfiguration span(PageSpan span, bool header) {
      final config = SemanticsConfiguration()
        ..label = span.label
        // The renderer lays every book out left to right.
        ..textDirection = TextDirection.ltr
        ..isHeader = header
        ..isImage = span.image;
      if (span.link case final point?) {
        config
          ..isLink = true
          ..onTap = () => onTapAt(point);
      }
      return config;
    }

    return [
      for (final (index, block) in blocks.indexed)
        block.spans.length == 1
            ? node(block.rect, index, span(block.spans.single, block.header))
            : node(
                block.rect,
                index,
                SemanticsConfiguration()..isHeader = block.header,
                [
                  for (final (index, part) in block.spans.indexed)
                    node(part.rect, index, span(part, block.header)),
                ],
              ),
    ];
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
    selection.paint(context, offset, _selectionColor);
  }
}
