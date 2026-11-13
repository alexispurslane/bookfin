// The word view of the PDF viewport's shown source page. See
// docs/plans/pdf-word-image-reflow.md, "The text under the images" and
// "Waiting, turns, the scrub deck and the scrub bar".
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'document.dart';
import 'pdf.dart';
import 'word_bands.dart';
import 'word_pages.dart';
import 'word_selection.dart';

/// The source page that [PdfWordScreens] opened, and what it learned of it.
class _OpenPage {
  _OpenPage(this.place, {required this.last})
    : moved = last,
      turned = last,
      forward = !last;

  /// The place that opened the page. Until the person moves, it is the
  /// page's place while the page's text cannot name a better one.
  final PdfAddress place;
  int get page => place.sourcePage;

  /// Whether the page opens on its last screen, after a turn back.
  final bool last;

  /// Whether the person turned or touched the page since it opened.
  bool moved;
  bool turned;

  /// The direction of the last turn, in which the next screen renders ahead.
  bool forward;

  ReflowPage? reflow;
  AttachedText? attached;
  WordPageText? text;

  /// The column of the page for the settings that it was laid out for, kept
  /// until the settings change, and the screen of it that is asked for.
  WordColumn? column;
  int screen = 0;

  /// Completes with whether the page's first screen showed, or with false
  /// when the page has no words to show.
  final shown = Completer<bool>();

  /// Whether the page has no words to show.
  bool gaveUp = false;

  void end() {
    if (!shown.isCompleted) shown.complete(false);
  }
}

/// The word view of the source page that a [PdfViewport] shows: which of
/// its screens shows, the place of that screen, and the waits for the
/// page's words and for its text. The session's PDF pager owns this state
/// and opens each requested page. Each screen that shows reports its place
/// through [onPlace]. When
/// the page's text attaches to the shown screen, the screen reports its
/// place again through [onRefinedPlace]: the same place under a better
/// name.
///
/// Places follow "The text under the images":
/// - Once the text attaches, the place of a screen is the first character
///   of its first piece that names text ([ReflowColumn.firstCharacter]),
///   or the page itself when none does.
/// - Before the text attaches, the place that opened the page is kept
///   until the person turns a screen. A turn then makes the
///   page itself the place.
/// - When the text attaches and the person did not move, the screen that
///   holds the opening place shows, in one move.
///
/// The last readable word screen stays while another screen's words are
/// on their way. With no previous word screen, the original page shows. It
/// has no words to show when it has no word geometry, or when its
/// geometry, analysis, column or bands fail, or when its text says that
/// its content does not reflow. The viewport then shows it as before the
/// word view: its text, or its original page.
class PdfWordScreens {
  PdfWordScreens(
    this.book, {
    required this.onPlace,
    required this.onRefinedPlace,
    required this.onGiveUp,
  }) {
    _pages = _newPages();
  }

  final PdfBook book;

  /// Reports the place of a screen that shows: the first screen of a page,
  /// and each screen that a turn or a new layout shows.
  final ValueChanged<PdfAddress> onPlace;

  /// Reports the place of the screen of the last [onPlace] report again,
  /// as the page's text names it once the text attaches. The screen did
  /// not change, so this is no move of the place.
  final ValueChanged<PdfAddress> onRefinedPlace;

  /// Reports that the shown page, whose words showed, has no words to show
  /// any more: a band failed, or its text says that it does not reflow.
  final VoidCallback onGiveUp;

  late PdfWordPages _pages;
  _OpenPage? _open;
  // Identity of the last screen of this open page acknowledged by a view.
  // Prepared images can outlive the view; readiness must never publish a place.
  WordScreen? _appeared;
  WordSettings? _settings;
  var _disposed = false;
  final _showing = ValueNotifier(false);
  final _waitingForText = ValueNotifier(false);
  final _text = ValueNotifier<WordScreenText?>(null);

  /// The reading text paired with the displayed column and screen, or null
  /// before attachment. Selection, semantics and read-aloud share it.
  ValueListenable<WordScreenText?> get text => _text;

  /// Whether the requested source page has shown its first word screen.
  /// False while that page waits, even if an earlier word screen remains.
  ValueListenable<bool> get showing => _showing;

  /// Whether the shown page waits for its text.
  ValueListenable<bool> get waitingForText => _waitingForText;

  /// The prepared screen, which [WordScreenView] draws. Preparation alone
  /// does not report a place; the view must acknowledge its completed frame.
  ValueListenable<WordScreen?> get screen => _pages.shown;

  /// The last word screen of this request acknowledged in a completed frame,
  /// or null before one appears. Its identity still names the reported place
  /// while another screen prepares, even if that preparation has finished.
  WordScreen? get appearedScreen => _appeared;

  /// The settings that the screens are laid out for, once [lay] gave them.
  WordSettings? get settings => _settings;

  /// Whether the word view shows the open page, or may still show it:
  /// its words are on their way or show.
  bool get covers => !(_open?.gaveUp ?? true);

  PdfWordPages _newPages() =>
      PdfWordPages(book)..shown.addListener(_screenPrepared);

  /// Opens the page of [place]: on its last screen when [last], and
  /// otherwise on its first screen until its text names the screen that
  /// holds [place].
  void open(PdfAddress place, {bool last = false}) {
    _pages.retainShown();
    _open?.end();
    final open = _open = _OpenPage(place, last: last);
    _appeared = null;
    _text.value = null;
    _showing.value = false;
    _waitingForText.value = true;
    unawaited(_prepare(open));
  }

  /// Whether [page] shows as words. It completes when the first screen of
  /// the open page shows, or when the page has no words to show.
  Future<bool> shows(int page) async {
    final open = _open;
    if (open == null || open.page != page) return false;
    return await open.shown.future && !open.gaveUp;
  }

  /// Lays the screens out for [settings], which the view measured. A shown
  /// page keeps its first shown word on the shown screen.
  void lay(WordSettings settings) {
    if (_disposed || settings == _settings) return;
    _pages.retainShown();
    _settings = settings;
    final open = _open;
    if (open != null && open.reflow != null && !open.gaveUp) {
      unawaited(_layOut(open));
    }
  }

  /// Shows the next screen of the shown page, or the previous one when not
  /// [forward]. False when the page's words do not show, or when no such
  /// screen is on the page.
  bool turn(bool forward) {
    final open = _open, column = open?.column;
    if (open == null || column == null || !_showing.value) return false;
    final next = open.screen + (forward ? 1 : -1);
    if (next < 0 || next >= column.column.screenCount) return false;
    open
      ..moved = true
      ..turned = true
      ..forward = forward
      ..screen = next;
    unawaited(_show(open));
    return true;
  }

  /// Records that the person touched the shown screen, so that the arrival
  /// of the text leaves the screen as it is.
  void touch() {
    if (!_showing.value && screen.value != null) return;
    _open?.moved = true;
  }

  /// Closes the open page and frees the band images.
  void leave() {
    _open?.end();
    _open = null;
    _appeared = null;
    _text.value = null;
    _showing.value = false;
    _waitingForText.value = false;
    _pages
      ..shown.removeListener(_screenPrepared)
      ..dispose();
    _pages = _newPages();
  }

  void dispose() {
    _disposed = true;
    _open?.end();
    _open = null;
    _appeared = null;
    _pages
      ..shown.removeListener(_screenPrepared)
      ..dispose();
    _showing.dispose();
    _waitingForText.dispose();
    _text.dispose();
  }

  /// Checks the open page, requested screen and displayed band ownership.
  /// A shown page has a view-acknowledged screen; its requested screen is inside
  /// its column. A closed controller has no open page. Pending page opens,
  /// turns and size changes keep the previous screen until bands arrive.
  void checkInvariants() {
    _pages.checkInvariants();
    final open = _open;
    if (_disposed && open != null) {
      throw StateError('A disposed word view has no open page.');
    }
    if (_showing.value != (_appeared != null) ||
        (_appeared != null &&
            (open == null || open.gaveUp || _appeared!.page != open.page))) {
      throw StateError('The displayed word screen belongs to the open page.');
    }
    final text = _text.value, shown = screen.value;
    if (text != null &&
        (shown == null ||
            !identical(text.column, shown.column.column) ||
            text.screen != shown.screen ||
            !identical(
              text.page.attached.attachment,
              open?.attached?.attachment,
            ))) {
      throw StateError(
        'The selectable text belongs to the displayed word screen.',
      );
    }
    final column = open?.column;
    if (column != null &&
        (open!.screen < 0 || open.screen >= column.column.screenCount)) {
      throw StateError('The requested word screen is inside its column.');
    }
  }

  Future<void> _prepare(_OpenPage open) async {
    final ReflowPage? reflow;
    try {
      reflow = await book.reflowPage(open.page);
    } on Exception {
      // A failed layout pass or analysis leaves the page to the viewport.
      if (identical(open, _open)) _giveUp(open);
      return;
    } catch (error, stack) {
      _reportError(open, error, stack);
      return;
    }
    if (!identical(open, _open)) return;
    if (reflow == null) {
      _giveUp(open);
      return;
    }
    open.reflow = reflow;
    unawaited(_attach(open, reflow));
    await _layOut(open);
  }

  Future<void> _attach(_OpenPage open, ReflowPage reflow) async {
    AttachedText? attached;
    try {
      attached = await reflow.attachedText();
      if (attached.attachment != null) {
        final plan = await book.hop(prepareWordText, (
          geometry: reflow.geometry,
          analysis: reflow.analysis,
          attached: attached,
        ));
        if (!identical(open, _open) || open.gaveUp) return;
        open.text = WordPageText(attached, plan);
      }
    } on Exception {
      // The words stay without text, as after a failed recognition.
    } catch (error, stack) {
      _reportError(open, error, stack);
      return;
    }
    if (!identical(open, _open) || open.gaveUp) return;
    open.attached = attached;
    _waitingForText.value = false;
    final status = attached?.text.status;
    if (status == PdfTextStatus.absent || status == PdfTextStatus.unreliable) {
      // The page's own content does not reflow, so it shows as printed.
      _giveUp(open);
      return;
    }
    final column = open.column;
    // Without a column, the first screen is chosen with the text.
    if (column == null) return;
    final character = open.moved ? null : _openingCharacter(open);
    final screen = character == null
        ? open.screen
        : column.column.screenAt(
            character,
            attached!.attachment!,
            reflow.analysis,
          );
    if (screen != open.screen) {
      open.screen = screen;
      return _show(open);
    }
    _publishText(open);
    if (_appeared != null && identical(_appeared, _pages.shown.value)) {
      onRefinedPlace(_placeOf(open));
    }
  }

  Future<void> _layOut(_OpenPage open) async {
    final settings = _settings;
    if (settings == null) return;
    final before = _showing.value ? _pages.shown.value : null;
    final WordColumn? column;
    try {
      column = await _pages.column(open.page, settings);
    } on Exception {
      if (identical(open, _open) && settings == _settings) _giveUp(open);
      return;
    } catch (error, stack) {
      _reportError(open, error, stack);
      return;
    }
    if (!identical(open, _open) || settings != _settings || open.gaveUp) {
      return;
    }
    if (column == null) {
      _giveUp(open);
      return;
    }
    open.column = column;
    open.screen = before != null && before.page == open.page
        ? column.column.screenShowing(before.column.column, before.screen)
        : open.last
        ? column.column.screenCount - 1
        : _openingScreen(open, column);
    await _show(open);
  }

  /// The character of the opening place in the page's text, or null while
  /// the text does not name it.
  int? _openingCharacter(_OpenPage open) {
    final attached = open.attached;
    if (attached == null || attached.attachment == null) return null;
    return book.resolveAddress(open.place, attached.text)?.character;
  }

  int _openingScreen(_OpenPage open, WordColumn column) {
    final character = open.moved ? null : _openingCharacter(open);
    return character == null
        ? 0
        : column.column.screenAt(
            character,
            open.attached!.attachment!,
            open.reflow!.analysis,
          );
  }

  Future<void> _show(_OpenPage open) async {
    final screen = open.screen, column = open.column!;
    try {
      await _pages.show(open.page, _settings!, screen, forward: open.forward);
    } on Exception {
      if (identical(open, _open) &&
          identical(open.column, column) &&
          open.screen == screen) {
        _giveUp(open);
      }
    } catch (error, stack) {
      _reportError(open, error, stack);
    }
  }

  bool _isRequested(WordScreen shown, _OpenPage open) =>
      !open.gaveUp &&
      shown.page == open.page &&
      identical(shown.column, open.column) &&
      shown.screen == open.screen;

  /// Pairs selection text with prepared images without claiming visibility.
  void _screenPrepared() {
    final open = _open, shown = _pages.shown.value;
    if (open != null && shown != null && _isRequested(shown, open)) {
      _publishText(open);
    }
  }

  /// Acknowledges [shown] after a view drew it in a completed frame.
  /// Only the current prepared, requested screen can report a changed place
  /// or release the first-screen wait. Repeated and retained-screen reports
  /// are ignored. Text may later refine this same displayed screen even
  /// while the view is absent; preparation of another screen cannot do so.
  void appeared(WordScreen shown) {
    final open = _open;
    if (_disposed ||
        open == null ||
        identical(_appeared, shown) ||
        !identical(_pages.shown.value, shown) ||
        !_isRequested(shown, open)) {
      return;
    }
    _appeared = shown;
    if (!open.shown.isCompleted) open.shown.complete(true);
    _publishText(open);
    _showing.value = true;
    onPlace(_placeOf(open));
  }

  /// The place of the shown screen of [open], by the rules of "The text
  /// under the images".
  PdfAddress _placeOf(_OpenPage open) {
    final attached = open.attached, attachment = attached?.attachment;
    if (!open.turned &&
        (attachment == null || _openingCharacter(open) == null)) {
      return open.place;
    }
    if (attachment == null) {
      return PdfAddress(open.page, 0, pageCount: book.pageCount);
    }
    final shown = _pages.shown.value!;
    final character = shown.column.column.firstCharacter(
      shown.screen,
      attachment,
      open.reflow!.analysis,
    );
    return book.addressFor(open.page, attached!.text, character ?? 0);
  }

  void _publishText(_OpenPage open) {
    final shown = _pages.shown.value, page = open.text;
    if (shown == null || page == null || shown.page != open.page) {
      return;
    }
    final before = _text.value;
    if (identical(before?.page, page) &&
        identical(before?.column, shown.column.column) &&
        before?.screen == shown.screen) {
      return;
    }
    _text.value = WordScreenText(page, shown.column.column, shown.screen);
  }

  void _reportError(_OpenPage open, Object error, StackTrace stack) {
    if (open.shown.isCompleted) Error.throwWithStackTrace(error, stack);
    open.shown.completeError(error, stack);
  }

  void _giveUp(_OpenPage open) {
    open.gaveUp = true;
    _appeared = null;
    _text.value = null;
    _pages.clearShown();
    _showing.value = false;
    _waitingForText.value = false;
    if (open.shown.isCompleted) {
      onGiveUp();
    } else {
      open.shown.complete(false);
    }
  }
}

/// The word view of the shown page: its screen, at whole device pixels
/// inside the reader's margins, with the thin progress line while the page
/// waits for its text, and [waiting] only without a readable word screen.
/// It measures the screens for [fontSize] and reports a touch on a screen.
class PdfWordView extends StatelessWidget {
  const PdfWordView({
    super.key,
    required this.screens,
    required this.fontSize,
    required this.waiting,
    required this.onLayout,
    required this.onAppeared,
    this.selectionKey,
  });
  final PdfWordScreens screens;
  final double fontSize;
  final Widget waiting;
  final ValueChanged<WordSettings> onLayout;

  /// Reports the exact prepared screen drawn in a completed content frame.
  final ValueChanged<WordScreen> onAppeared;
  final GlobalKey? selectionKey;

  /// The margins of a screen in logical pixels, as the text view's.
  static const _side = 20.0, _top = 12.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final ratio = MediaQuery.devicePixelRatioOf(context);
      // Whole device pixels keep a level word's pixels one to one.
      final side = (_side * ratio).round() / ratio;
      final top = (_top * ratio).round() / ratio;
      final settings = (
        width: math.max(1.0, constraints.maxWidth - 2 * side),
        fontSize: fontSize,
        screenHeight: math.max(1.0, constraints.maxHeight - 2 * top),
        devicePixelRatio: ratio,
      );
      if (settings != screens.settings) {
        // The size starts layout work, so the screens hear of it after
        // this frame.
        WidgetsBinding.instance.addPostFrameCallback((_) => onLayout(settings));
      }
      return ValueListenableBuilder<WordScreen?>(
        valueListenable: screens.screen,
        builder: (context, shown, view) {
          if (shown == null) return waiting;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) onAppeared(shown);
          });
          return view!;
        },
        child: _screen(side, top),
      );
    },
  );

  Widget _screen(double side, double top) => Stack(
    children: [
      Positioned.fill(
        child: Padding(
          padding: EdgeInsets.fromLTRB(side, top, side, top),
          child: ValueListenableBuilder<WordScreen?>(
            valueListenable: screens.screen,
            builder: (_, shown, view) => shown == null
                ? const SizedBox.shrink()
                : _DevicePixelOrigin(
                    ratio: shown.settings.devicePixelRatio,
                    child: view,
                  ),
            child: WordSelectable(
              key: selectionKey,
              text: screens.text,
              child: WordScreenView(screen: screens.screen),
            ),
          ),
        ),
      ),
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: ValueListenableBuilder<bool>(
          valueListenable: screens.waitingForText,
          builder: (_, waiting, _) => waiting
              ? const LinearProgressIndicator(
                  minHeight: 2,
                  semanticsLabel: 'Recognizing the text of this page',
                )
              : const SizedBox.shrink(),
        ),
      ),
    ],
  );
}

class _DevicePixelOrigin extends SingleChildRenderObjectWidget {
  const _DevicePixelOrigin({required this.ratio, required super.child});
  final double ratio;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _PixelOriginBox(ratio);

  @override
  void updateRenderObject(BuildContext context, _PixelOriginBox renderObject) {
    renderObject.ratio = ratio;
  }
}

class _PixelOriginBox extends RenderProxyBox {
  _PixelOriginBox(this._ratio);
  double _ratio;

  set ratio(double value) {
    if (_ratio == value) return;
    _ratio = value;
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  Offset get _shift {
    final origin = localToGlobal(Offset.zero);
    return Offset(
      (origin.dx * _ratio).round() / _ratio - origin.dx,
      (origin.dy * _ratio).round() / _ratio - origin.dy,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child != null) context.paintChild(child!, offset + _shift);
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final shift = _shift;
    transform.translateByDouble(shift.dx, shift.dy, 0, 1);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      child != null &&
      result.addWithPaintOffset(
        offset: _shift,
        position: position,
        hitTest: (result, position) =>
            child!.hitTest(result, position: position),
      );
}
