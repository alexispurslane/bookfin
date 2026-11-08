// The phone benchmark of the native EPUB renderer trial (ticket boo-ju83).
// It is a separate app (dev.bookfin.epubtrial) that leaves Bookfin alone.
// On start it lays out and draws every bundled public-domain book twice and
// prints the results to logcat, one `EPUBTRIAL` line each.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

// native_epub links to the trial renderer in Bookfin's source tree.
import 'native_epub/benchmark.dart';
import 'native_epub/book.dart';
import 'native_epub/layout.dart';

const books = [
  'pg-46-christmas-carol',
  'pg-84-frankenstein',
  'se-alices-adventures-in-wonderland',
  'se-frankenstein',
  'se-moby-dick',
  'se-poetry',
  'se-pride-and-prejudice',
  'showcase-frost',
];

void main() {
  runApp(const _Status());
  WidgetsBinding.instance.addPostFrameCallback((_) => _run());
}

final _status = ValueNotifier('Running the EPUB trial benchmark');

class _Status extends StatelessWidget {
  const _Status();
  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: Center(
      child: ValueListenableBuilder(
        valueListenable: _status,
        builder: (context, value, _) => Text(
          value,
          style: const TextStyle(color: Color(0xffffffff), fontSize: 18),
        ),
      ),
    ),
  );
}

void _log(String kind, Object value) =>
    // ignore: avoid_print
    print('EPUBTRIAL $kind ${jsonEncode(value)}');

Future<void> _run() async {
  final ratio =
      WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;
  const theme = PageTheme();
  _log('device', {'pixelRatio': ratio, 'rssMiB': ProcessInfo.currentRss >> 20});
  for (final pass in [1, 2]) {
    for (final name in books) {
      final data = await rootBundle.load('books/$name.epub');
      final book = TrialBook.open(data.buffer.asUint8List());
      final timing = await benchmarkBook(name, book, theme, pixelRatio: ratio);
      final json = timing.toJson();
      final sections = json.remove('perSection') as List;
      _log('book', {'pass': pass, ...json});
      for (final section in sections) {
        _log('section', {'pass': pass, 'book': name, ...section as Map});
      }
      if (pass == 2) {
        final retained = await retainedMemory(book, theme);
        _log('retained', {
          'book': name,
          'sections': retained.sections,
          'characters': retained.characters,
          'MiB': retained.bytes / 1048576,
        });
      }
      _status.value = 'Pass $pass: $name done';
    }
  }
  _log('done', {'rssMiB': ProcessInfo.currentRss >> 20});
  _status.value = 'EPUB trial benchmark done';
}
