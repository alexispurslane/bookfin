import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  runApp(MaterialApp(home: PdfViewer.asset('assets/simple.pdf')));
}
