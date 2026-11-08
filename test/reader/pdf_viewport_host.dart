import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/pdf.dart';
import 'package:bookfin/reader/pdf_viewport.dart';
import 'package:flutter/material.dart';
import 'package:flutter_epub_viewer/navigation.dart' show ContentsEntry;

/// A [PdfViewport] under a stand-in for the reader screen's controller
/// part. It keeps the reflow choice, which starts at [reflow], and sends
/// recognition choices to the document's text supply, as the screen does
/// through the session.
class PdfViewportHost extends StatefulWidget {
  const PdfViewportHost({
    super.key,
    required this.book,
    required this.fontSize,
    required this.onReady,
    required this.onAddress,
    this.initial,
    this.reflow = false,
  });
  final PdfBook book;
  final double fontSize;
  final PdfAddress? initial;
  final void Function(DocumentNavigator, List<ContentsEntry>) onReady;
  final ValueChanged<PdfAddress> onAddress;
  final bool reflow;
  @override
  State<PdfViewportHost> createState() => _PdfViewportHostState();
}

class _PdfViewportHostState extends State<PdfViewportHost> {
  late bool _reflow = widget.reflow;
  @override
  Widget build(BuildContext context) => PdfViewport(
    book: widget.book,
    fontSize: widget.fontSize,
    initial: widget.initial,
    onReady: widget.onReady,
    onAddress: widget.onAddress,
    reflow: _reflow,
    onReflow: (on) => setState(() => _reflow = on),
    onCancelRecognition: () => widget.book.textSupply?.cancel(),
    onRetryRecognition: (page) => widget.book.textSupply?.retry(page),
  );
}
