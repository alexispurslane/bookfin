import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'page_swipes.dart';
import 'pdf.dart';
import 'pdf_pager.dart';
import 'pdf_text_view.dart';
import 'pdf_word_view.dart';
import 'selection.dart';
import 'word_bands.dart';
import 'word_pages.dart';
import 'word_selection.dart';

/// Draws the session's PDF page and reports gestures, measurements and
/// completed content frames. It owns only selection and zoom UI state.
/// Removing this view does not release navigation, text or page data.
class PdfViewport extends StatefulWidget {
  const PdfViewport({
    super.key,
    required this.pager,
    required this.fontSize,
    required this.onLayout,
    required this.onWordLayout,
    required this.onAppeared,
    required this.onRetry,
    required this.onTouch,
    required this.onCopy,
    required this.onTap,
    required this.onTurn,
  });

  /// Page data and its narrow change signal, owned by the reader session.
  final PdfPager pager;
  final double fontSize;

  /// Reports raster width in device pixels, text area in logical pixels,
  /// and text style. The controller prepares layout for this frame.
  final void Function(double, Size, TextStyle) onLayout;
  final ValueChanged<WordSettings> onWordLayout;

  /// Reports the request identity whose content entered a completed frame,
  /// with the exact prepared screen when that content consists of word images.
  final void Function(int generation, {WordScreen? words}) onAppeared;
  final VoidCallback onRetry;
  final VoidCallback onTouch;
  final ValueChanged<String> onCopy;
  final VoidCallback onTap;
  final ValueChanged<bool> onTurn;

  @override
  State<PdfViewport> createState() => _PdfViewportState();
}

class _PdfViewportState extends State<PdfViewport> {
  final _wordSelection = GlobalKey();
  final _selectionArea = GlobalKey<SelectionAreaState>();
  bool _selectedAtDown = false;
  WordSelection? get _selection =>
      (_wordSelection.currentContext?.findRenderObject()
              as RenderWordSelectable?)
          ?.selection;

  void _copy() {
    if (_selection?.text case final text?) widget.onCopy(text);
  }

  void _tap() {
    if (_selectedAtDown) {
      _selectionArea.currentState?.selectableRegion.clearSelection();
    } else {
      widget.onTap();
    }
  }

  final _zoom = TransformationController();
  bool get _zoomed => _zoom.value.getMaxScaleOnAxis() > 1.01;
  (PdfPager, int, bool)? _zoomPage;

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  /// Called from content builders, not from construction of an unused
  /// waiting widget. A finished raster alone must never count as visibility.
  void _pageInFrame() {
    final pager = widget.pager;
    final generation = pager.generation;
    final report = widget.onAppeared;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(widget.pager, pager)) report(generation);
    });
  }

  Widget _reflowText() {
    final shown = widget.pager.textScreen!;
    _pageInFrame();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: PdfTextView(screens: shown.layout, screen: shown.index),
    );
  }

  bool get _usingText => widget.pager.usingText;
  bool get _usingWords => widget.pager.usingWords;
  bool get _loading => widget.pager.loading;
  int get _page => widget.pager.page;
  String? get _failure => widget.pager.failure;
  String? get _reflowProblem => widget.pager.reflowProblem;
  PdfWordScreens get _words => widget.pager.words;

  /// The original page, the reflowed text, or what stands in their place.
  Widget _shownPage() {
    if (_usingText) return _reflowText();
    final failure = switch (_failure) {
      null => null,
      final message => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(message, textAlign: TextAlign.center),
          ),
          TextButton(
            onPressed: widget.onRetry,
            child: const Text('Retry source page'),
          ),
        ],
      ),
    };
    if (widget.pager.image == null) {
      return Center(child: failure ?? const CircularProgressIndicator());
    }
    final page = Builder(
      builder: (_) {
        _pageInFrame();
        return Semantics(
          label: 'Original source page $_page',
          image: true,
          child: InteractiveViewer(
            transformationController: _zoom,
            minScale: 1,
            maxScale: 6,
            child: Center(
              child: RawImage(image: widget.pager.image, fit: BoxFit.contain),
            ),
          ),
        );
      },
    );
    return failure == null
        ? page
        : Column(
            children: [
              failure,
              Expanded(child: page),
            ],
          );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.pager.pageChanges,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final pager = widget.pager;
        final zoomPage = (pager, pager.generation, pager.trimMargins);
        if (_zoomPage != zoomPage) {
          _zoomPage = zoomPage;
          _zoom.value = Matrix4.identity();
        }
        widget.onLayout(
          MediaQuery.sizeOf(context).width *
              MediaQuery.devicePixelRatioOf(context),
          Size(
            math.max(1.0, constraints.maxWidth - 40),
            math.max(1.0, constraints.maxHeight - 24),
          ),
          TextStyle(
            fontFamily: 'Source Serif 4',
            fontFamilyFallback: const ['Noto Serif'],
            fontSize: widget.fontSize,
            height: 1.55,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        );
        return _content();
      },
    ),
  );

  Widget _content() => Semantics(
    container: true,
    // The page, its quiet line and its text keep their own nodes.
    explicitChildNodes: true,
    onScrollLeft: () => widget.onTurn(true),
    onScrollRight: () => widget.onTurn(false),
    child: PageSwipes(
      onTurn: widget.onTurn,
      swipes: () => !_zoomed && !(_selection?.selecting ?? false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // The page's own semantics turn pages. The screen offers the
        // controls to a screen reader.
        excludeFromSemantics: true,
        onTap: _usingWords ? null : _tap,
        child: Listener(
          onPointerDown: (_) {
            _selectedAtDown = _selection?.selecting ?? false;
            if (_usingWords) widget.onTouch();
          },
          child: _view(),
        ),
      ),
    ),
  );

  /// The shown page in the chosen view.
  Widget _view() {
    if (_usingWords) {
      final pager = widget.pager;
      final generation = pager.generation;
      final report = widget.onAppeared;
      return ReaderCopyArea(
        area: _selectionArea,
        onCopy: _copy,
        child: ReaderTapArea(
          onTap: (_) => _tap(),
          child: PdfWordView(
            screens: _words,
            selectionKey: _wordSelection,
            fontSize: widget.fontSize,
            waiting: _wordWaiting(),
            onLayout: widget.onWordLayout,
            onAppeared: (shown) {
              if (mounted && identical(widget.pager, pager)) {
                report(generation, words: shown);
              }
            },
          ),
        ),
      );
    }
    if (widget.pager.view == PdfPageView.original || _usingText) {
      return _shownPage();
    }
    // The reflow view shows the original page while the text is on its way,
    // when the page's own content does not reflow, and when reflow failed
    // on the page. Only a failure puts a quiet line above it.
    final problem = _reflowProblem;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (problem != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: Text(
              problem,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          )
        else if (widget.pager.recognizing case final recognizing?)
          ValueListenableBuilder<bool>(
            valueListenable: recognizing,
            builder: (_, recognizing, _) => recognizing && _loading
                ? const LinearProgressIndicator(
                    minHeight: 2,
                    semanticsLabel: 'Recognizing the text of this page',
                  )
                : const SizedBox.shrink(),
          ),
        Expanded(child: _shownPage()),
      ],
    );
  }

  Widget _wordWaiting() => Stack(
    children: [
      Positioned.fill(child: _shownPage()),
      const Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: LinearProgressIndicator(minHeight: 2),
      ),
    ],
  );
}
