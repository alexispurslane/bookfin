import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/foundation/theme.dart';
import 'package:bookfin/playback/records.dart';
import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/screen.dart';
import 'package:bookfin/reader/session.dart' show ContentsEntry;
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

  testWidgets('a bookmark row reports a tap as a return to its place, and its '
      'menu reports Edit and Delete', (tester) async {
    final restored = <TextBookmark>[];
    final edited = <TextBookmark>[];
    final deleted = <TextBookmark>[];
    await _show(
      tester,
      ReaderBookmarksPanel(
        bookmarks: [_mark],
        onRestore: restored.add,
        onEdit: edited.add,
        onDelete: deleted.add,
      ),
    );
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

  group('the reader control bar', () {
    /// Shows the control bar. Every control is on unless it is named in
    /// [off], and each tap adds its control to [tapped].
    Future<void> showControls(
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
        ReaderControls(
          onContents: report('Contents'),
          onSearch: report('Search book'),
          onSmaller: report('Smaller text'),
          onLarger: report('Larger text'),
          onBookmark: report('Bookmark this place'),
          onBookmarks: report('Reading bookmarks'),
          night: night,
          onNightChanged: (night) => tapped.add('night $night'),
          reflow: reflow,
          onReflowChanged: (reflow) => tapped.add('reflow $reflow'),
        ),
      );
    }

    const controls = [
      'Contents',
      'Search book',
      'Smaller text',
      'Larger text',
      'Bookmark this place',
      'Reading bookmarks',
    ];

    testWidgets('reports each tap through the callback of its control', (
      tester,
    ) async {
      final tapped = <String>[];
      await showControls(tester, tapped);
      for (final control in controls) {
        await tester.tap(find.byTooltip(control));
      }
      await tester.tap(find.byTooltip('Night reading theme'));
      expect(tapped, [...controls, 'night true']);
    });

    testWidgets('a control that is off shows but reports no tap', (
      tester,
    ) async {
      final tapped = <String>[];
      await showControls(
        tester,
        tapped,
        off: {'Smaller text', 'Bookmark this place'},
      );
      await tester.tap(find.byTooltip('Smaller text'));
      await tester.tap(find.byTooltip('Bookmark this place'));
      await tester.tap(find.byTooltip('Larger text'));
      expect(tapped, ['Larger text']);
    });

    testWidgets('in the night theme the theme control offers the cream theme', (
      tester,
    ) async {
      final tapped = <String>[];
      await showControls(tester, tapped, night: true);
      expect(find.byTooltip('Night reading theme'), findsNothing);
      await tester.tap(find.byTooltip('Cream reading theme'));
      expect(tapped, ['night false']);
    });

    IconData? icon(String tooltip) => find
        .descendant(of: find.byTooltip(tooltip), matching: find.byType(Icon))
        .evaluate()
        .map((element) => (element.widget as Icon).icon)
        .single;

    testWidgets('a book that is not a PDF has no reflow control', (
      tester,
    ) async {
      final tapped = <String>[];
      await showControls(tester, tapped);
      expect(find.byTooltip('Reflow text'), findsNothing);
      expect(find.byTooltip('Original page'), findsNothing);
    });

    testWidgets('while the original PDF page shows, the reflow control offers '
        'Reflow text', (tester) async {
      final tapped = <String>[];
      await showControls(tester, tapped, reflow: false);
      expect(find.byTooltip('Original page'), findsNothing);
      expect(icon('Reflow text'), Icons.article_outlined);
      await tester.tap(find.byTooltip('Reflow text'));
      expect(tapped, ['reflow true']);
    });

    testWidgets(
      'while reflowed text shows, the reflow control offers Original page',
      (tester) async {
        final tapped = <String>[];
        await showControls(tester, tapped, reflow: true);
        expect(find.byTooltip('Reflow text'), findsNothing);
        expect(icon('Original page'), Icons.picture_as_pdf_outlined);
        await tester.tap(find.byTooltip('Original page'));
        expect(tapped, ['reflow false']);
      },
    );

    testWidgets('the reflow control sits after the text size controls', (
      tester,
    ) async {
      await showControls(tester, [], reflow: false);
      final tooltips = tester
          .widgetList<IconButton>(find.byType(IconButton))
          .map((button) => button.tooltip)
          .toList();
      expect(
        tooltips.indexOf('Reflow text'),
        tooltips.indexOf('Larger text') + 1,
      );
    });
  });
}
