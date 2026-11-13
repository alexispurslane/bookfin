import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/pdf.dart';
import 'package:bookfin/reader/pdf_viewport.dart';
import 'package:bookfin/reader/screen.dart' show ReaderSettingsPanel;
import 'package:flutter/material.dart';

import 'pdf_test_controller.dart';

/// A [PdfViewport] under a stand-in for the reader screen's controller
/// part. It keeps the reflow choice, which starts at [view], and offers it
/// in the reader's settings panel, shown under the viewport. It tells the
/// document's text supply when the viewport stops waiting, as the screen does.
class PdfViewportHost extends StatefulWidget {
  const PdfViewportHost({
    super.key,
    required this.book,
    required this.fontSize,
    required this.onReady,
    required this.onAddress,
    this.initial,
    this.view = PdfPageView.original,
  });
  final PdfBook book;
  final double fontSize;
  final PdfAddress? initial;
  final void Function(DocumentNavigator, List<ContentsEntry>) onReady;
  final ValueChanged<PdfAddress> onAddress;
  final PdfPageView view;
  @override
  State<PdfViewportHost> createState() => _PdfViewportHostState();
}

class _PdfViewportHostState extends State<PdfViewportHost> {
  late PdfPageView _view = widget.view;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: PdfTestController(
          book: widget.book,
          fontSize: widget.fontSize,
          initial: widget.initial,
          onReady: widget.onReady,
          onAddress: widget.onAddress,
          // The stand-in owner takes a refined place as the shown place.
          onRefinedAddress: widget.onAddress,
          view: _view,
          onCancelRecognition: () => widget.book.textSupply?.cancel(),
          onTap: () {},
          onTurn: (_) {},
        ),
      ),
      ReaderSettingsPanel(
        fontSize: widget.fontSize,
        onSmaller: null,
        onLarger: null,
        night: false,
        onNightChanged: (_) {},
        pdfView: _view,
        onPdfViewChanged: (view) => setState(() => _view = view),
      ),
    ],
  );
}
