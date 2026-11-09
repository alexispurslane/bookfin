// The native EPUB viewport: a leaf widget that draws the pager's shown page
// and reports what the person did.
//
// It causes one effect of its own: from its layout, it presents the page
// settings to the pager, which is a request for pages, like an Image that
// resolves its image. Every other action goes up through a callback: a tap,
// a link, a page turn and a copy. PageSwipes, which every reader view
// shares, reports the swipes. A render object subscribes to the shown
// page, so a new page repaints the viewport, updates its semantics and
// clears its selection without a rebuild.
//
// The page is the one selectable of a SelectionArea, which owns the
// selection gestures, the handles and the menu. Its Copy and the copy
// shortcut report the selected text through onCopy, and the screen writes
// the clipboard.
//
// EpubNoteView draws a note that the pager laid out for the note sheet. It
// shares the page's semantics nodes, selection and Copy, and has no
// gestures of its own.
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../page_swipes.dart';
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

  /// A tap on an internal link: its destination for `contents`, relative
  /// to the package document's directory, and whether it is a note
  /// reference.
  final ValueChanged<EpubLink> onLink;

  /// The person chose Copy for the selected text.
  final ValueChanged<String> onCopy;

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

  /// Whether text was selected when the tap in progress went down.
  bool _selectedAtDown = false;

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
  Widget build(BuildContext context) => _CopyArea(
    area: _area,
    focusNode: _focus,
    onCopy: _copy,
    // The selection region claims horizontal drags, so the swipe watches the
    // pointers. A drag with text selected adjusts the selection.
    child: PageSwipes(
      onTurn: widget.onTurn,
      swipes: () => !(_selection?.selecting ?? false),
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
                  ..onTapUp = (details) =>
                      _tapAt(details.localPosition, selected: _selectedAtDown),
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
  );
}

/// A selection region whose Copy, in its menu and by its shortcut, calls
/// [onCopy], and which writes no clipboard of its own. Its menu offers Copy
/// and Select all. On Android, Copy ends the selection, and elsewhere it
/// hides the menu, as Flutter's own menu does.
class _CopyArea extends StatelessWidget {
  const _CopyArea({
    this.area,
    this.focusNode,
    required this.onCopy,
    required this.child,
  });
  final GlobalKey<SelectionAreaState>? area;
  final FocusNode? focusNode;
  final VoidCallback onCopy;
  final Widget child;

  Widget _menu(BuildContext context, SelectableRegionState region) {
    void copied() {
      onCopy();
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

  @override
  Widget build(BuildContext context) => Actions(
    actions: {
      CopySelectionTextIntent: CallbackAction<CopySelectionTextIntent>(
        onInvoke: (_) => onCopy(),
      ),
    },
    child: SelectionArea(
      key: area,
      focusNode: focusNode,
      contextMenuBuilder: _menu,
      child: child,
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
      _blocks = page == null
          ? const []
          : _blockNodes(pageBlocks(page), size, onTapAt);
    }
    node.updateWith(config: config, childrenInInversePaintOrder: _blocks);
  }

  @override
  void clearSemantics() {
    super.clearSemantics();
    _read = null;
    _blocks = const [];
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

/// A semantics node for each of [blocks] of a page [size] big, in their
/// order. A block of one span is one node. A block of several, such as a
/// paragraph with a link, holds a node for each span. With [onTapAt], a
/// link is marked as one, and its tap action taps the page at the link.
List<SemanticsNode> _blockNodes(
  List<PageBlock> blocks,
  Size size,
  ValueChanged<Offset>? onTapAt,
) {
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
    if ((span.link, onTapAt) case (final point?, final tap?)) {
      config
        ..isLink = true
        ..onTap = () => tap(point);
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

/// Draws [note] at its own size: as wide as the width that it was laid out
/// at, and as tall as its text. A screen reader reads it block by block, as
/// it reads a page, and its links are plain text. The person can select
/// its text, and Copy reports the selected text through [onCopy].
class EpubNoteView extends StatefulWidget {
  const EpubNoteView({super.key, required this.note, required this.onCopy});
  final LaidNote note;

  /// The person chose Copy for the selected text.
  final ValueChanged<String> onCopy;

  @override
  State<EpubNoteView> createState() => _EpubNoteViewState();
}

class _EpubNoteViewState extends State<EpubNoteView> {
  final _note = GlobalKey();

  void _copy() {
    final note = _note.currentContext?.findRenderObject() as _RenderNote?;
    if (note?.selection.text case final text?) widget.onCopy(text);
  }

  @override
  Widget build(BuildContext context) => _CopyArea(
    onCopy: _copy,
    child: _Note(key: _note, note: widget.note),
  );
}

class _Note extends LeafRenderObjectWidget {
  const _Note({super.key, required this.note});
  final LaidNote note;

  @override
  _RenderNote createRenderObject(BuildContext context) => _RenderNote(note)
    ..registrar = SelectionContainer.maybeOf(context)
    ..selectionColor = _Page._selectionColor(context);

  @override
  void updateRenderObject(BuildContext context, _RenderNote note) => note
    ..note = this.note
    ..registrar = SelectionContainer.maybeOf(context)
    ..selectionColor = _Page._selectionColor(context);
}

/// Paints a note's picture at the note's size, with its selection in
/// [selectionColor], and gives a screen reader its blocks.
class _RenderNote extends RenderBox {
  _RenderNote(this._note) {
    selection.page = _note.page;
  }

  late final selection = PageSelection(this);

  set registrar(SelectionRegistrar? value) => selection.registrar = value;

  Color _selectionColor = DefaultSelectionStyle.defaultColor;
  set selectionColor(Color value) {
    if (value == _selectionColor) return;
    _selectionColor = value;
    markNeedsPaint();
  }

  LaidNote _note;
  set note(LaidNote value) {
    if (identical(value, _note)) return;
    _note = value;
    selection.page = value.page;
    markNeedsLayout();
    markNeedsSemanticsUpdate();
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.constrain(Size(_note.page.settings.width, _note.page.height));

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void dispose() {
    selection.dispose();
    super.dispose();
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config.isSemanticBoundary = true;
  }

  @override
  void assembleSemanticsNode(
    SemanticsNode node,
    SemanticsConfiguration config,
    Iterable<SemanticsNode> children,
  ) => node.updateWith(
    config: config,
    childrenInInversePaintOrder: _blockNodes(
      pageBlocks(_note.page),
      size,
      null,
    ),
  );

  @override
  void paint(PaintingContext context, Offset offset) {
    context.canvas
      ..save()
      ..clipRect(offset & size)
      ..translate(offset.dx, offset.dy)
      ..drawPicture(_note.picture)
      ..restore();
    selection.paint(context, offset, _selectionColor);
  }
}
