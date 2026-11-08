import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/foundation/theme.dart';
import 'package:bookfin/playback/playback.dart' show RecentListening;
import 'package:bookfin/playback/recent.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The recent listening list takes its entries as a listenable value, and no
// Playback. So these tests feed it plain values.

Book _book(String title) => Book(
  id: title,
  title: title,
  author: 'A. Writer',
  editions: [
    Edition(
      id: '$title-audio',
      kind: EditionKind.audio,
      label: 'Audiobook',
      files: const [],
      memberIds: const [],
    ),
  ],
);

final _tide = _book('Tidewater');
final _frost = _book('First Frost');
final _ink = _book('Inkwell');

/// [book] listened to [daysAgo] days before now, with [elapsedMs] of
/// [totalMs] heard, or with unknown progress.
RecentProgress _listened(
  Book book,
  int daysAgo, {
  int? elapsedMs,
  int totalMs = 7200000,
}) => (
  entry: (
    book: book,
    edition: book.editions.single,
    at: DateTime.now().subtract(Duration(days: daysAgo)),
  ),
  progress: elapsedMs == null ? null : (elapsedMs: elapsedMs, totalMs: totalMs),
);

void main() {
  late ValueNotifier<List<RecentProgress>> recent;
  late List<RecentListening> resumed;
  setUp(() {
    recent = ValueNotifier([_listened(_tide, 1), _listened(_frost, 2)]);
    resumed = [];
  });
  tearDown(() => recent.dispose());

  Future<void> show(WidgetTester tester, {Book? open}) => tester.pumpWidget(
    MaterialApp(
      theme: bookfinTheme(Brightness.light),
      home: Scaffold(
        body: RecentListeningList(
          recent: recent,
          open: open,
          onResume: resumed.add,
          empty: const Text('Nothing else yet'),
        ),
      ),
    ),
  );

  List<String> rows(WidgetTester tester) => [
    for (final row in tester.widgetList<RecentListeningRow>(
      find.byType(RecentListeningRow),
    ))
      row.entry.book.title,
  ];

  testWidgets('lists each recent book, newest first, under its label', (
    tester,
  ) async {
    await show(tester);
    expect(find.text('RECENTLY LISTENED'), findsOneWidget);
    expect(rows(tester), ['Tidewater', 'First Frost']);
  });

  testWidgets('leaves out the open book', (tester) async {
    await show(tester, open: _tide);
    expect(rows(tester), ['First Frost']);
  });

  testWidgets('shows the empty widget when no other book was listened to', (
    tester,
  ) async {
    recent.value = [_listened(_tide, 1)];
    await show(tester, open: _tide);
    expect(find.text('Nothing else yet'), findsOneWidget);
    expect(find.text('RECENTLY LISTENED'), findsNothing);
  });

  testWidgets('follows a new listening without a rebuild from its owner', (
    tester,
  ) async {
    await show(tester);
    recent.value = [_listened(_ink, 0), ...recent.value];
    await tester.pump();
    expect(rows(tester), ['Inkwell', 'Tidewater', 'First Frost']);
  });

  testWidgets('shows the time left from each book’s own progress', (
    tester,
  ) async {
    recent.value = [
      _listened(_tide, 1, elapsedMs: 3600000),
      _listened(_frost, 2),
    ];
    await show(tester);
    expect(
      find.descendant(
        of: find.widgetWithText(RecentListeningRow, 'Tidewater'),
        matching: find.textContaining('1 h 0 m left'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('left'), findsOneWidget);
  });

  testWidgets('a tap on a row reports its entry to resume', (tester) async {
    await show(tester);
    await tester.tap(find.byTooltip('Resume First Frost'));
    expect(resumed, [recent.value[1].entry]);
  });
}
