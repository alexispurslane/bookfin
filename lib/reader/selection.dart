import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Selection events, carets and handle layers for one displayed page.
/// The page supplies four queries: a caret at a point, a range at a point,
/// the reading text of a range and the geometry of a range. Extent and
/// offsets describe the page's character coordinate system.
///
/// Both carets are absent or inside [extent]. [checkInvariants] checks this
/// on demand. The page calls [updateSelection] when its content changes.
mixin ReaderSelection<Caret extends Object> on ChangeNotifier
    implements Selectable {
  RenderBox get box;
  (Caret, Caret)? get extent;
  int offsetOf(Caret caret);
  int compareCarets(Caret first, Caret second);
  Caret? caretFor(ui.Offset point);
  (Caret, Caret)? rangeFor(ui.Offset point, TextGranularity granularity);
  String textFor(Caret start, Caret end);
  SelectionGeometry geometryFor(Caret start, Caret end);

  Caret? _start;
  Caret? _end;
  LayerLink? _startHandle;
  LayerLink? _endHandle;
  SelectionGeometry _geometry = const SelectionGeometry(
    status: SelectionStatus.none,
    hasContent: false,
  );

  bool get selecting => _start != null && _start != _end;
  @protected
  Iterable<Caret> get selectionCarets => [?_start, ?_end];
  String? get text => selecting ? textFor(_start!, _end!) : null;
  List<ui.Rect> get rects => _geometry.selectionRects;

  void checkInvariants() {
    if ((_start == null) != (_end == null)) {
      throw StateError('One selection caret is set without the other.');
    }
    for (final caret in selectionCarets) {
      final range = extent;
      if (range == null ||
          compareCarets(caret, range.$1) < 0 ||
          compareCarets(caret, range.$2) > 0) {
        throw StateError('A selection caret is outside the displayed text.');
      }
    }
  }

  @override
  SelectionGeometry get value => _geometry;
  @override
  Size get size => box.size;
  @override
  Matrix4 getTransformTo(RenderObject? ancestor) =>
      box.getTransformTo(ancestor);
  @override
  List<ui.Rect> get boundingBoxes => [ui.Offset.zero & box.size];
  @override
  int get contentLength => extent == null ? 0 : offsetOf(extent!.$2);
  @override
  SelectedContent? getSelectedContent() {
    final selected = text;
    return selected == null ? null : SelectedContent(plainText: selected);
  }

  @override
  SelectedContentRange? getSelection() => _start == null
      ? null
      : SelectedContentRange(
          startOffset: offsetOf(_start!),
          endOffset: offsetOf(_end!),
        );

  @override
  void pushHandleLayers(LayerLink? startHandle, LayerLink? endHandle) {
    if (!box.attached) return;
    if (startHandle == _startHandle && endHandle == _endHandle) return;
    _startHandle = startHandle;
    _endHandle = endHandle;
    box.markNeedsPaint();
  }

  @override
  SelectionResult dispatchSelectionEvent(SelectionEvent event) {
    final result = switch (event) {
      ClearSelectionEvent() => _clear(),
      _ when extent == null => SelectionResult.none,
      SelectWordSelectionEvent(:final globalPosition) => _select(
        rangeFor(box.globalToLocal(globalPosition), TextGranularity.word),
        globalPosition,
      ),
      SelectParagraphSelectionEvent(:final globalPosition) => _select(
        rangeFor(box.globalToLocal(globalPosition), TextGranularity.paragraph),
        globalPosition,
      ),
      SelectionEdgeUpdateEvent() => _moveEdge(event),
      SelectAllSelectionEvent() => _select(extent, null),
      _ => SelectionResult.none,
    };
    updateSelection();
    return result;
  }

  void paint(PaintingContext context, ui.Offset offset, ui.Color color) {
    if (selecting) {
      final paint = ui.Paint()..color = color;
      for (final rect in rects) {
        context.canvas.drawRect(rect.shift(offset), paint);
      }
    }
    void leader(LayerLink? link, SelectionPoint? point) {
      if (link == null || point == null) return;
      context.pushLayer(
        LeaderLayer(link: link, offset: offset + point.localPosition),
        (_, _) {},
        ui.Offset.zero,
      );
    }

    leader(_startHandle, _geometry.startSelectionPoint);
    leader(_endHandle, _geometry.endSelectionPoint);
  }

  void updateSelection({bool clear = false}) {
    if (clear) _start = _end = null;
    final next = _start == null
        ? SelectionGeometry(
            status: SelectionStatus.none,
            hasContent: extent != null,
          )
        : geometryFor(_start!, _end!);
    if (next == _geometry) return;
    _geometry = next;
    box.markNeedsPaint();
    notifyListeners();
  }

  SelectionResult _select((Caret, Caret)? range, ui.Offset? global) {
    if (range == null || range.$1 == range.$2) return SelectionResult.none;
    _start = range.$1;
    _end = range.$2;
    return global == null
        ? SelectionResult.none
        : SelectionUtils.getResultBasedOnRect(
            ui.Offset.zero & box.size,
            box.globalToLocal(global),
          );
  }

  SelectionResult _clear() {
    _start = _end = null;
    return SelectionResult.none;
  }

  SelectionResult _moveEdge(SelectionEdgeUpdateEvent event) {
    final local = box.globalToLocal(event.globalPosition);
    final caret = caretFor(local);
    if (caret == null) return SelectionResult.none;
    final moving = event.type == SelectionEventType.startEdgeUpdate;
    final other = (moving ? _end : _start) ?? caret;
    final range = switch (event.granularity) {
      TextGranularity.document => extent,
      TextGranularity.character || TextGranularity.line => (caret, caret),
      _ => rangeFor(local, event.granularity),
    };
    if (range == null) return SelectionResult.none;
    final away = compareCarets(other, caret) <= 0 ? range.$2 : range.$1;
    if (moving) {
      _start = away;
      _end ??= other;
    } else {
      _end = away;
      _start ??= other;
    }
    return SelectionUtils.getResultBasedOnRect(
      ui.Offset.zero & box.size,
      local,
    );
  }
}

/// The shared reader Copy menu and shortcut. Clipboard writes belong to
/// the screen controller, through [onCopy], not to this widget.
class ReaderCopyArea extends StatelessWidget {
  const ReaderCopyArea({
    super.key,
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
    final items = region.contextMenuButtonItems;
    // Flutter can reopen a retained toolbar after its selectable content
    // disappears. An empty menu has no selection anchors to position it.
    if (items.isEmpty) return const SizedBox.shrink();

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
        for (final item in items)
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

/// Reports page taps inside a selection region without claiming its
/// long presses and handle drags. Page semantics report their own actions.
class ReaderTapArea extends StatelessWidget {
  const ReaderTapArea({
    super.key,
    this.onTapDown,
    required this.onTap,
    required this.child,
  });
  final VoidCallback? onTapDown;
  final ValueChanged<Offset> onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => RawGestureDetector(
    behavior: HitTestBehavior.opaque,
    excludeFromSemantics: true,
    gestures: {
      TapGestureRecognizer:
          GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
            () => TapGestureRecognizer(debugOwner: this),
            (tap) => tap
              ..onTapDown = ((_) => onTapDown?.call())
              ..onTapUp = (details) => onTap(details.localPosition),
          ),
    },
    child: child,
  );
}
