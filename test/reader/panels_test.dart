import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/foundation/theme.dart';
import 'package:bookfin/playback/records.dart';
import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The reader panels take values and callbacks, and no ReaderSession. So
// these tests build each panel with no session at all: a panel that tried to
// reach one would not compile.

Future<void> _show(WidgetTester tester, Widget panel) => tester.pumpWidget(
  MaterialApp(
    theme: bookfinTheme(Brightness.light),
    home: Scaffold(body: panel),
  ),
);

final _mark = TextBookmark(
  id: 'river-mark',
  position: const TextPosition(
    editionId: 'edition',
    sourceKey: 'source',
    revision: 'r1',
    anchor: '{}',
  ),
  createdAt: DateTime.utc(2026, 11, 7, 9),
  title: 'River mark',
  note: 'Where the road bends',
);

void main() {
  testWidgets('a contents row reports the place that it names', (tester) async {
    final chosen = <String>[];
    await _show(
      tester,
      ReaderContentsPanel(
        contents: const [
          ContentsEntry('River heading', 'one.xhtml#start'),
          ContentsEntry('The bridge', 'two.xhtml', depth: 1),
        ],
        onContents: chosen.add,
        bookmarks: const [],
        onRestore: (_) {},
        onEdit: (_) {},
        onDelete: (_) {},
      ),
    );
    await tester.tap(find.text('The bridge'));
    await tester.pump();
    expect(chosen, ['two.xhtml']);
  });

  testWidgets('the search panel reports a submitted query, a chosen hit and '
      'Cancel search', (tester) async {
    final queries = <String>[];
    final opened = <ReaderHit>[];
    var cancels = 0;
    final hit = ReaderHit(PdfAddress(2, 0), 'the river follows the road');
    await _show(
      tester,
      ReaderSearchPanel(
        searching: false,
        hits: [hit],
        error: null,
        onSearch: queries.add,
        onOpenHit: opened.add,
        onCancelSearch: () => cancels++,
      ),
    );
    await tester.enterText(find.byType(TextField), 'river');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(queries, ['river']);

    await tester.tap(find.text('the river follows the road'));
    await tester.pump();
    expect(opened, [hit]);

    await tester.tap(find.byTooltip('Cancel search'));
    await tester.pump();
    expect(cancels, 1);
  });

  testWidgets('the search panel says No matches only after a query found '
      'nothing', (tester) async {
    Widget panel({required bool searching}) => ReaderSearchPanel(
      searching: searching,
      hits: const [],
      error: null,
      onSearch: (_) {},
      onOpenHit: (_) {},
      onCancelSearch: () {},
    );
    await _show(tester, panel(searching: false));
    expect(find.text('No matches.'), findsNothing);
    await tester.enterText(find.byType(TextField), 'river');
    await _show(tester, panel(searching: true));
    expect(find.text('No matches.'), findsNothing);
    expect(find.bySemanticsLabel('Searching the book'), findsOneWidget);
    await _show(tester, panel(searching: false));
    expect(find.text('No matches.'), findsOneWidget);
  });

  testWidgets('a bookmark row on the Bookmarks tab reports a tap as a return '
      'to its place, and its menu reports Edit and Delete', (tester) async {
    final restored = <TextBookmark>[];
    final edited = <TextBookmark>[];
    final deleted = <TextBookmark>[];
    await _show(
      tester,
      ReaderContentsPanel(
        contents: const [ContentsEntry('River heading', 'one.xhtml')],
        onContents: (_) {},
        bookmarks: [_mark],
        onRestore: restored.add,
        onEdit: edited.add,
        onDelete: deleted.add,
      ),
    );
    await tester.tap(find.widgetWithText(Tab, 'Bookmarks'));
    await tester.pumpAndSettle();
    expect(find.text('Where the road bends'), findsOneWidget);
    await tester.tap(find.text('River mark'));
    await tester.pump();
    expect(restored, [_mark]);

    await tester.tap(find.byTooltip('Edit reading bookmark'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit title and note'));
    await tester.pumpAndSettle();
    expect(edited, [_mark]);

    await tester.tap(find.byTooltip('Edit reading bookmark'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(deleted, [_mark]);
    expect(restored, hasLength(1), reason: 'a menu choice is not a tap');
  });

  group('the reader tool row', () {
    /// Shows the tool row. Every tool is on unless it is named in [off], and
    /// each tap adds its tool to [tapped].
    Future<void> showTools(
      WidgetTester tester,
      List<String> tapped, {
      Set<String> off = const {},
      Widget? audio,
    }) {
      VoidCallback? report(String tool) =>
          off.contains(tool) ? null : () => tapped.add(tool);
      return _show(
        tester,
        ReaderTools(
          onContents: report('Contents'),
          onSearch: report('Search book'),
          onSettings: report('Reading settings'),
          onBookmark: report('Bookmark this place'),
          audio: audio,
        ),
      );
    }

    const tools = [
      'Contents',
      'Search book',
      'Reading settings',
      'Bookmark this place',
    ];

    testWidgets('reports each tap through the callback of its tool', (
      tester,
    ) async {
      final tapped = <String>[];
      await showTools(tester, tapped);
      for (final tool in tools) {
        await tester.tap(find.byTooltip(tool));
      }
      expect(tapped, tools);
    });

    testWidgets('a tool that is off shows but reports no tap', (tester) async {
      final tapped = <String>[];
      await showTools(
        tester,
        tapped,
        off: {'Reading settings', 'Bookmark this place'},
      );
      await tester.tap(find.byTooltip('Reading settings'));
      await tester.tap(find.byTooltip('Bookmark this place'));
      await tester.tap(find.byTooltip('Contents'));
      expect(tapped, ['Contents']);
    });

    testWidgets('puts the audio slot last, after the four tools', (
      tester,
    ) async {
      await showTools(
        tester,
        [],
        audio: const SizedBox.square(key: Key('audio'), dimension: 48),
      );
      final audio = tester.getRect(find.byKey(const Key('audio')));
      for (final tool in tools) {
        expect(
          tester.getRect(find.byTooltip(tool)).right,
          lessThanOrEqualTo(audio.left),
          reason: tool,
        );
      }
    });
  });

  group('the reading settings panel', () {
    /// Shows the panel. Both size buttons are on unless named in [off], and
    /// each choice adds itself to [tapped].
    Future<void> showSettings(
      WidgetTester tester,
      List<String> tapped, {
      Set<String> off = const {},
      bool night = false,
      bool? reflow,
    }) {
      VoidCallback? report(String control) =>
          off.contains(control) ? null : () => tapped.add(control);
      return _show(
        tester,
        ReaderSettingsPanel(
          fontSize: 20,
          onSmaller: report('Smaller text'),
          onLarger: report('Larger text'),
          night: night,
          onNightChanged: (night) => tapped.add('night $night'),
          reflow: reflow,
          onReflowChanged: (reflow) => tapped.add('reflow $reflow'),
        ),
      );
    }

    testWidgets('shows the text size and reports the size buttons', (
      tester,
    ) async {
      final tapped = <String>[];
      await showSettings(tester, tapped, off: {'Smaller text'});
      expect(find.text('20'), findsOneWidget);
      await tester.tap(find.byTooltip('Smaller text'));
      await tester.tap(find.byTooltip('Larger text'));
      expect(tapped, ['Larger text']);
    });

    testWidgets('marks the shown theme and reports the other', (tester) async {
      final tapped = <String>[];
      await showSettings(tester, tapped, night: true);
      await tester.tap(find.byTooltip('Night reading theme'));
      await tester.pump();
      expect(tapped, isEmpty, reason: 'The night theme already shows.');
      await tester.tap(find.byTooltip('Cream reading theme'));
      expect(tapped, ['night false']);
    });

    testWidgets('a book that is not a PDF has no reflow choice', (
      tester,
    ) async {
      await showSettings(tester, []);
      expect(find.byTooltip('Reflow text'), findsNothing);
      expect(find.byTooltip('Original page'), findsNothing);
    });

    testWidgets('a PDF offers its original page and reflowed text, and '
        'reports the other view', (tester) async {
      final tapped = <String>[];
      await showSettings(tester, tapped, reflow: false);
      await tester.tap(find.byTooltip('Original page'));
      await tester.pump();
      expect(tapped, isEmpty, reason: 'The original page already shows.');
      await tester.tap(find.byTooltip('Reflow text'));
      expect(tapped, ['reflow true']);
    });
  });
}
