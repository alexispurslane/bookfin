import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'column_layout.dart';
import 'page_analysis.dart';
import 'page_geometry.dart';
import 'pdf.dart';
import 'selection.dart';

/// Paragraph and region ranges prepared off the UI isolate. They contain
/// no copy of the reading text or its attachment.
typedef WordTextPlan = ({
  List<(int, int)> paragraphs,
  List<(int, int)?> regions,
});

/// The original attached reading text paired with its prepared ranges.
class WordPageText {
  WordPageText(this.attached, this.plan) {
    if (attached.attachment == null ||
        attached.text.status != PdfTextStatus.candidate) {
      throw ArgumentError(
        'Word selection needs the page\'s attached reading text.',
      );
    }
  }
  final AttachedText attached;
  final WordTextPlan plan;

  (int, int) rangeOf(int word) =>
      (attached.attachment![word * 2], attached.attachment![word * 2 + 1]);

  (int, int)? rangeOfPiece(ReflowColumn column, int piece) {
    final word = column.word(piece);
    return word >= 0 ? rangeOf(word) : plan.regions[column.region(piece)];
  }

  String textBetween(int first, int end) {
    final offsets = attached.text.sourceOffsets;
    int indexOf(int character) {
      var low = 0, high = offsets.length;
      while (low < high) {
        final middle = (low + high) ~/ 2;
        if (offsets[middle] < character) {
          low = middle + 1;
        } else {
          high = middle;
        }
      }
      return low;
    }

    return attached.text.text.substring(indexOf(first), indexOf(end));
  }
}

/// Prepares paragraph character ranges from the layout's paragraph rules.
WordTextPlan prepareWordText(
  ({PageGeometry geometry, PageAnalysis analysis, AttachedText attached}) input,
) {
  final attachment = input.attached.attachment;
  if (attachment == null ||
      attachment.length != input.analysis.wordRegions.length * 2) {
    throw ArgumentError(
      'Word selection needs the geometry\'s text attachment.',
    );
  }
  final regions = List<(int, int)?>.filled(input.analysis.regionCount, null);
  for (var word = 0; word < input.analysis.wordRegions.length; word++) {
    final region = input.analysis.wordRegions[word];
    final first = attachment[word * 2], end = attachment[word * 2 + 1];
    if (region < 0 || first == end) continue;
    regions[region] = (regions[region]?.$1 ?? first, end);
  }
  final paragraphs = <(int, int)>[];
  for (final (first, end) in wordParagraphs(input.geometry, input.analysis)) {
    int? start, finish;
    for (var word = first; word < end; word++) {
      if (attachment[word * 2] == attachment[word * 2 + 1]) continue;
      start ??= attachment[word * 2];
      finish = attachment[word * 2 + 1];
    }
    if (start != null) paragraphs.add((start, finish!));
  }
  return (paragraphs: paragraphs, regions: regions);
}

/// Reading-text queries for one displayed screen. Character offsets count
/// UTF-16 code units in PdfText.source. Rectangles use logical pixels from
/// the screen's top left. Empty attachment ranges never name selectable ink.
class WordScreenText {
  WordScreenText(this.page, this.column, this.screen) {
    final first = column.lineStarts[column.screenStarts[screen]];
    final end = column.lineStarts[column.screenStarts[screen + 1]];
    for (var piece = first; piece < end; piece++) {
      final rect = column
          .target(piece)
          .shift(Offset(0, -column.screenTop(screen)));
      final range = page.rangeOfPiece(column, piece);
      if (range == null || range.$1 == range.$2) {
        _empty.add(rect);
      } else {
        _pieces.add((rect: rect, first: range.$1, end: range.$2));
      }
    }
  }

  final WordPageText page;
  final ReflowColumn column;
  final int screen;
  final _pieces = <({Rect rect, int first, int end})>[];
  final _empty = <Rect>[];

  (int, int)? get extent =>
      _pieces.isEmpty ? null : (_pieces.first.first, _pieces.last.end);

  ({Rect rect, int first, int end})? _nearest(Offset point) {
    ({Rect rect, int first, int end})? nearest;
    var distance = double.infinity;
    for (final piece in _pieces) {
      final rect = piece.rect;
      final dx = point.dx - point.dx.clamp(rect.left, rect.right);
      final dy = point.dy - point.dy.clamp(rect.top, rect.bottom);
      final next = dx * dx + dy * dy;
      if (next < distance) {
        nearest = piece;
        distance = next;
      }
    }
    return nearest;
  }

  int? caretAt(Offset point) {
    final piece = _nearest(point);
    if (piece == null) return null;
    return piece.first +
        ((point.dx - piece.rect.left) /
                piece.rect.width *
                (piece.end - piece.first))
            .round()
            .clamp(0, piece.end - piece.first);
  }

  (int, int)? rangeAt(Offset point, TextGranularity granularity) {
    if (_empty.any((rect) => rect.contains(point))) return null;
    final piece = _nearest(point);
    if (piece == null) return null;
    final caret = caretAt(point)!.clamp(piece.first, piece.end - 1);
    if (granularity == TextGranularity.paragraph) {
      for (final (first, end) in page.plan.paragraphs) {
        if (first <= caret && caret < end) {
          return (math.max(first, extent!.$1), math.min(end, extent!.$2));
        }
      }
    }
    final source = page.attached.text.source;
    var first = caret, end = caret;
    while (first > extent!.$1 && !_space(source[first - 1])) {
      first--;
    }
    while (end < extent!.$2 && !_space(source[end])) {
      end++;
    }
    return first < end ? (first, end) : null;
  }

  static bool _space(String character) => character.trim().isEmpty;

  String textBetween(int start, int end) =>
      page.textBetween(math.min(start, end), math.max(start, end));

  /// The covered parts of the displayed pieces, also used by read-aloud.
  /// [start] is inclusive and [end] is exclusive, in source UTF-16 units.
  /// Reversed ranges are accepted. An empty range has no rectangles.
  List<Rect> rectsFor(int start, int end) {
    final first = math.min(start, end), finish = math.max(start, end);
    return [
      for (final piece in _pieces)
        if (math.max(first, piece.first) < math.min(finish, piece.end))
          Rect.fromLTRB(
            piece.rect.left +
                piece.rect.width *
                    (math.max(first, piece.first) - piece.first) /
                    (piece.end - piece.first),
            piece.rect.top,
            piece.rect.left +
                piece.rect.width *
                    (math.min(finish, piece.end) - piece.first) /
                    (piece.end - piece.first),
            piece.rect.bottom,
          ),
    ];
  }

  SelectionPoint pointAt(int caret, bool left) {
    final piece = _pieces.firstWhere(
      (piece) => left
          ? piece.first <= caret && caret < piece.end
          : piece.first < caret && caret <= piece.end,
      orElse: () => _pieces.lastWhere(
        (piece) => piece.first < caret,
        orElse: () => _pieces.first,
      ),
    );
    return SelectionPoint(
      localPosition: Offset(
        piece.rect.left +
            piece.rect.width *
                (caret - piece.first).clamp(0, piece.end - piece.first) /
                (piece.end - piece.first),
        piece.rect.bottom,
      ),
      lineHeight: piece.rect.height,
      handleType: left
          ? TextSelectionHandleType.left
          : TextSelectionHandleType.right,
    );
  }

  Iterable<({String text, Rect rect})> get paragraphs sync* {
    final range = extent;
    if (range == null) return;
    for (final (first, end) in page.plan.paragraphs) {
      final from = math.max(first, range.$1), to = math.min(end, range.$2);
      final rects = rectsFor(from, to);
      if (from >= to || rects.isEmpty) continue;
      yield (
        text: textBetween(from, to),
        rect: rects.reduce((bounds, rect) => bounds.expandToInclude(rect)),
      );
    }
  }
}

class WordSelection
    with ChangeNotifier, ReaderSelection<int>, SelectionRegistrant {
  WordSelection(this.box);
  @override
  final RenderBox box;
  WordScreenText? _screen;
  WordScreenText? get screen => _screen;
  set screen(WordScreenText? value) {
    if (identical(value, _screen)) return;
    _screen = value;
    updateSelection(clear: true);
  }

  @override
  (int, int)? get extent => _screen?.extent;
  @override
  int offsetOf(int caret) => caret - extent!.$1;
  @override
  int compareCarets(int first, int second) => first.compareTo(second);
  @override
  int? caretFor(Offset point) => _screen?.caretAt(point);
  @override
  (int, int)? rangeFor(Offset point, TextGranularity granularity) =>
      _screen?.rangeAt(point, granularity);
  @override
  String textFor(int start, int end) => _screen!.textBetween(start, end);
  @override
  SelectionGeometry geometryFor(int start, int end) => SelectionGeometry(
    startSelectionPoint: _screen!.pointAt(start, start <= end),
    endSelectionPoint: _screen!.pointAt(end, start > end),
    selectionRects: _screen!.rectsFor(start, end),
    status: start == end
        ? SelectionStatus.collapsed
        : SelectionStatus.uncollapsed,
    hasContent: true,
  );
}

/// Adds selection and one semantics node per shown paragraph to word ink.
/// The caller owns the text signal and writes copied text through its action.
class WordSelectable extends SingleChildRenderObjectWidget {
  const WordSelectable({super.key, required this.text, required super.child});
  final ValueListenable<WordScreenText?> text;

  @override
  RenderWordSelectable createRenderObject(BuildContext context) =>
      RenderWordSelectable(text)
        ..selection.registrar = SelectionContainer.maybeOf(context)
        ..selectionColor =
            DefaultSelectionStyle.of(context).selectionColor ??
            DefaultSelectionStyle.defaultColor;

  @override
  void updateRenderObject(
    BuildContext context,
    RenderWordSelectable renderObject,
  ) {
    renderObject
      ..text = text
      ..selection.registrar = SelectionContainer.maybeOf(context)
      ..selectionColor =
          DefaultSelectionStyle.of(context).selectionColor ??
          DefaultSelectionStyle.defaultColor;
  }
}

class RenderWordSelectable extends RenderProxyBox {
  RenderWordSelectable(this._text) {
    selection.screen = _text.value;
  }
  late final selection = WordSelection(this);
  ValueListenable<WordScreenText?> _text;
  Color selectionColor = DefaultSelectionStyle.defaultColor;
  List<SemanticsNode>? _paragraphs;

  set text(ValueListenable<WordScreenText?> value) {
    if (identical(value, _text)) return;
    if (attached) _text.removeListener(_changed);
    _text = value;
    if (attached) _text.addListener(_changed);
    _changed();
  }

  void _changed() {
    selection.screen = _text.value;
    _paragraphs = null;
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  @override
  bool hitTestSelf(Offset position) => true;
  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _text.addListener(_changed);
  }

  @override
  void detach() {
    _text.removeListener(_changed);
    super.detach();
  }

  @override
  void dispose() {
    selection.dispose();
    super.dispose();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    selection.paint(context, offset, selectionColor);
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config.isSemanticBoundary = true;
    config.explicitChildNodes = true;
  }

  @override
  void assembleSemanticsNode(
    SemanticsNode node,
    SemanticsConfiguration config,
    Iterable<SemanticsNode> children,
  ) {
    _paragraphs ??= [
      for (final paragraph
          in _text.value?.paragraphs ?? const <({String text, Rect rect})>[])
        SemanticsNode()
          ..rect = paragraph.rect.intersect(Offset.zero & size)
          ..updateWith(
            config: SemanticsConfiguration()
              ..isSemanticBoundary = true
              ..textDirection = TextDirection.ltr
              ..label = paragraph.text,
          ),
    ];
    node.updateWith(config: config, childrenInInversePaintOrder: _paragraphs!);
  }

  @override
  void clearSemantics() {
    super.clearSemantics();
    _paragraphs = null;
  }
}
