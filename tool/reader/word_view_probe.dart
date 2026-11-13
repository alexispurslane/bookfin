import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show FrameTiming;

import 'package:bookfin/downloads/downloads.dart';
import 'package:bookfin/foundation/theme.dart';
import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/ocr.dart';
import 'package:bookfin/reader/pdf.dart';
import 'package:bookfin/reader/pdf_pager.dart';
import 'package:bookfin/reader/pdf_viewport.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _fixtures = String.fromEnvironment(
  'WORD_FIXTURES',
  defaultValue: 'http://127.0.0.1:8593',
);

String _digest(Uint8List bytes) => sha256.convert(bytes).toString();

void main() => runApp(const _Probe());

class _Probe extends StatefulWidget {
  const _Probe();

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  PdfBook? _book;
  PdfPager? _navigator;
  String _name = 'footnote-page.pdf';
  String? _failure;
  bool _night = false;
  PdfPageView _view = PdfPageView.pageWords;
  PdfAddress? _address;
  double _fontSize = 20;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addTimingsCallback(_frames);
    unawaited(_open(_name));
  }

  // Probe-only measurements. Profile-mode frame work is reported separately
  // from navigation latency; emulator results are not phone benchmarks.
  void _frames(List<FrameTiming> frames) {
    for (final frame in frames) {
      debugPrint(
        'WORD_FRAME ${jsonEncode({'buildUs': frame.buildDuration.inMicroseconds, 'rasterUs': frame.rasterDuration.inMicroseconds, 'totalUs': frame.totalSpan.inMicroseconds})}',
      );
    }
  }

  Future<void> _turn(bool forward) async {
    final before = _address?.toJson();
    final watch = Stopwatch()..start();
    await _navigator?.move(forward);
    await WidgetsBinding.instance.endOfFrame;
    debugPrint(
      'WORD_TURN ${jsonEncode({'fixture': _name, 'view': _view.name, 'size': _fontSize, 'forward': forward, 'before': before, 'after': _address?.toJson(), 'elapsedUs': watch.elapsedMicroseconds})}',
    );
  }

  Future<void> _open(String name) async {
    final request = ++_request;
    setState(() {
      _name = name;
      _failure = null;
    });
    final client = HttpClient();
    try {
      final response = await (await client.getUrl(
        Uri.parse('$_fixtures/$name'),
      )).close();
      if (response.statusCode != 200) throw StateError('Missing fixture $name');
      final bytes = await consolidateHttpClientResponseBytes(response);
      final digest = await compute(_digest, bytes);
      final directory = await Directory.systemTemp.createTemp('word-view-');
      final file = await File('${directory.path}/$name').writeAsBytes(bytes);
      final supply = BundledEnglishText();
      final book = await PdfRuntime.instance.open(
        file.path,
        digest,
        textSupply: supply,
      );
      supply.bind(
        (read) => read(
          VerifiedFile(file.uri, digest),
          () => mounted && request == _request,
        ),
      );
      if (!mounted || request != _request) {
        await book.dispose();
        return;
      }
      final previous = _book;
      _navigator?.dispose();
      setState(() {
        _book = book;
        _navigator = PdfPager(
          book,
          view: _view,
          onAddress: (address) {
            _address = address;
            debugPrint('WORD_VIEW ${address.sourcePage}:${address.character}');
          },
          onRefinedAddress: (address) => _address = address,
          onCancelRecognition: () => book.textSupply?.cancel(),
        );
      });
      if (previous != null) await previous.dispose();
    } catch (error) {
      if (mounted && request == _request) {
        setState(() => _failure = '$error');
      }
    } finally {
      client.close();
    }
  }

  @override
  void dispose() {
    _request++;
    WidgetsBinding.instance.removeTimingsCallback(_frames);
    _navigator?.dispose();
    unawaited(_book?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: bookfinTheme(_night ? Brightness.dark : Brightness.light),
    home: Scaffold(
      appBar: AppBar(
        title: Text(_name.startsWith('footnote') ? 'Scan' : 'Text layer'),
        actions: [
          TextButton(
            onPressed: () => unawaited(
              _open(
                _name.startsWith('footnote')
                    ? 'equation-page.pdf'
                    : 'footnote-page.pdf',
              ),
            ),
            child: const Text('Fixture'),
          ),
          TextButton(
            onPressed: () => setState(() => _night = !_night),
            child: Text(_night ? 'Cream' : 'Night'),
          ),
          TextButton(
            onPressed: () => setState(() {
              _fontSize = switch (_fontSize) {
                14 => 20,
                20 => 40,
                _ => 14,
              };
            }),
            child: Text('${_fontSize.toInt()}'),
          ),
          IconButton(
            tooltip: 'View: ${_view.name}',
            onPressed: () => setState(() {
              _view = switch (_view) {
                PdfPageView.original => PdfPageView.pageWords,
                PdfPageView.pageWords => PdfPageView.text,
                PdfPageView.text => PdfPageView.original,
              };
              _navigator?.configure(view: _view, trimMargins: true);
            }),
            icon: const Icon(Icons.chrome_reader_mode_outlined),
          ),
        ],
      ),
      body: _failure != null
          ? Center(child: Text(_failure!))
          : _book == null
          ? const Center(child: CircularProgressIndicator())
          : PdfViewport(
              key: ObjectKey(_book),
              pager: _navigator!,
              fontSize: _fontSize,
              onLayout: _navigator!.layout,
              onWordLayout: _navigator!.words.lay,
              onAppeared: _navigator!.appeared,
              onRetry: _navigator!.retryPage,
              onTouch: _navigator!.words.touch,
              onCopy: (text) =>
                  unawaited(Clipboard.setData(ClipboardData(text: text))),
              onTap: () {},
              onTurn: (forward) => unawaited(_turn(forward)),
            ),
    ),
  );
}
