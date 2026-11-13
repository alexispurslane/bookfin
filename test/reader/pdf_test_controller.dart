import 'dart:async';

import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/pdf.dart';
import 'package:bookfin/reader/pdf_pager.dart';
import 'package:bookfin/reader/pdf_viewport.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A standalone controller for viewport fixtures. Production creates its
/// pager in ReaderSession; these fixtures exercise the same owner without
/// catalog or persistence setup. Rebuilding a view retains its pager.
class PdfTestController extends StatefulWidget {
  const PdfTestController({
    super.key,
    required this.book,
    required this.fontSize,
    required this.onReady,
    required this.onAddress,
    required this.onRefinedAddress,
    required this.view,
    required this.onCancelRecognition,
    required this.onTap,
    required this.onTurn,
    this.initial,
    this.trimMargins = true,
  });
  final PdfBook book;
  final double fontSize;
  final PdfAddress? initial;
  final void Function(DocumentNavigator, List<ContentsEntry>) onReady;
  final ValueChanged<PdfAddress> onAddress;
  final ValueChanged<PdfAddress> onRefinedAddress;
  final PdfPageView view;
  final bool trimMargins;
  final VoidCallback onCancelRecognition;
  final VoidCallback onTap;
  final ValueChanged<bool> onTurn;

  @override
  State<PdfTestController> createState() => _PdfTestControllerState();
}

class _PdfTestControllerState extends State<PdfTestController> {
  late final PdfPager pager;

  @override
  void initState() {
    super.initState();
    pager = PdfPager(
      widget.book,
      initial: widget.initial,
      view: widget.view,
      trimMargins: widget.trimMargins,
      onAddress: (address) => widget.onAddress(address),
      onRefinedAddress: (address) => widget.onRefinedAddress(address),
      onCancelRecognition: () => widget.onCancelRecognition(),
    );
    scheduleMicrotask(() {
      if (!mounted) return;
      widget.onReady(pager, [
        for (var page = 1; page <= widget.book.pageCount; page++)
          ContentsEntry('Source page $page', 'page:$page'),
      ]);
    });
  }

  @override
  void didUpdateWidget(PdfTestController oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.view != oldWidget.view ||
        widget.trimMargins != oldWidget.trimMargins) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          pager.configure(view: widget.view, trimMargins: widget.trimMargins);
        }
      });
    }
  }

  @override
  void dispose() {
    pager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PdfViewport(
    pager: pager,
    fontSize: widget.fontSize,
    onLayout: pager.layout,
    onWordLayout: pager.words.lay,
    onAppeared: pager.appeared,
    onRetry: pager.retryPage,
    onTouch: pager.words.touch,
    onCopy: (text) => unawaited(Clipboard.setData(ClipboardData(text: text))),
    onTap: widget.onTap,
    onTurn: widget.onTurn,
  );
}
