import 'package:bookfin/foundation/theme.dart';
import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/pdf.dart';
import 'package:bookfin/reader/screen.dart';
import 'package:flutter/material.dart' hide TextPosition;
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

  testWidgets('the search panel reports a submitted query and a chosen '
      'hit', (tester) async {
    final queries = <String>[];
    final opened = <ReaderHit>[];
    final hit = ReaderHit(PdfAddress(2, 0), 'the river follows the road');
    await _show(
      tester,
      ReaderSearchPanel(
        searching: false,
        hits: [hit],
        error: null,
        onSearch: queries.add,
        onOpenHit: opened.add,
      ),
    );
    await tester.enterText(find.byType(TextField), 'river');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(queries, ['river']);

    await tester.tap(find.text('the river follows the road'));
    await tester.pump();
    expect(opened, [hit]);
  });

  testWidgets('the search panel says No matches only after a query found '
      'nothing', (tester) async {
    Widget panel({required bool searching}) => ReaderSearchPanel(
      searching: searching,
      hits: const [],
      error: null,
      onSearch: (_) {},
      onOpenHit: (_) {},
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

  group('the reader tool row', () {
    /// Shows the tool row. Every tool is on unless it is named in [off], and
    /// each tap adds its tool to [tapped].
    Future<void> showTools(
      WidgetTester tester,
      List<String> tapped, {
      Set<String> off = const {},
      bool bookmarked = false,
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
          onBookmark: report(bookmarked ? 'Bookmarked' : 'Bookmark this place'),
          bookmarked: bookmarked,
          onHistory: report('History'),
          audio: audio,
        ),
      );
    }

    const tools = [
      'Contents',
      'Search book',
      'Reading settings',
      'Bookmark this place',
      'History',
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

    testWidgets('a bookmarked page fills the Bookmark tool\'s icon, names it '
        'Bookmarked, and reports its tap', (tester) async {
      final tapped = <String>[];
      await showTools(tester, tapped, bookmarked: true);
      expect(find.byTooltip('Bookmark this place'), findsNothing);
      expect(find.byIcon(Icons.bookmark_rounded), findsOneWidget);
      await tester.tap(find.byTooltip('Bookmarked'));
      expect(tapped, ['Bookmarked']);
    });

    testWidgets('puts the audio slot last, after the five tools', (
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
      PdfPageView? pdfView,
      double scale = 1,
      double? width,
    }) {
      VoidCallback? report(String control) =>
          off.contains(control) ? null : () => tapped.add(control);
      return _show(
        tester,
        MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: SizedBox(
            width: width,
            child: ReaderSettingsPanel(
              fontSize: 20,
              onSmaller: report('Smaller text'),
              onLarger: report('Larger text'),
              night: night,
              onNightChanged: (night) => tapped.add('night $night'),
              pdfView: pdfView,
              onPdfViewChanged: (view) => tapped.add('view ${view.name}'),
            ),
          ),
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
      expect(find.byTooltip('Page words'), findsNothing);
      expect(find.byTooltip('Original page'), findsNothing);
      expect(find.text('Pages'), findsNothing);
      expect(find.text('Page words'), findsNothing);
      expect(find.text('Text'), findsNothing);
    });

    testWidgets('the Theme row stacks full labels at the largest text size', (
      tester,
    ) async {
      final tapped = <String>[];
      await showSettings(tester, tapped, width: 320, scale: 3.2);
      final cream = find.byTooltip('Cream reading theme');
      final night = find.byTooltip('Night reading theme');
      expect(
        tester.getRect(night).top,
        greaterThanOrEqualTo(tester.getRect(cream).bottom),
      );
      expect(find.byIcon(Icons.light_mode_outlined), findsNothing);
      expect(find.byIcon(Icons.dark_mode_outlined), findsNothing);
      for (final button in [cream, night]) {
        expect(tester.getSize(button).width, greaterThanOrEqualTo(48));
        expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
      }
      await tester.tap(night);
      expect(tapped, ['night true']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a PDF offers its original page, page words and text, and '
        'reports the other view', (tester) async {
      final tapped = <String>[];
      await showSettings(tester, tapped, pdfView: PdfPageView.original);
      expect(find.text('Original'), findsOneWidget);
      expect(find.text('Page words'), findsOneWidget);
      expect(find.text('Text'), findsOneWidget);
      await tester.tap(find.byTooltip('Original page'));
      await tester.pump();
      expect(tapped, isEmpty, reason: 'The original page already shows.');
      await tester.tap(find.byTooltip('Page words'));
      await tester.tap(find.byTooltip('Text'));
      expect(tapped, ['view pageWords', 'view text']);
    });

    testWidgets('all three PDF views stay readable and tappable on a narrow '
        'phone at the largest text size', (tester) async {
      final tapped = <String>[];
      await showSettings(
        tester,
        tapped,
        pdfView: PdfPageView.original,
        width: 320,
        scale: 3.2,
      );
      final choices = [
        find.byTooltip('Original page'),
        find.byTooltip('Page words'),
        find.byTooltip('Text'),
      ];
      for (var index = 1; index < choices.length; index++) {
        expect(
          tester.getRect(choices[index]).top,
          greaterThanOrEqualTo(tester.getRect(choices[index - 1]).bottom),
        );
      }
      for (final choice in choices) {
        await tester.ensureVisible(choice);
        final bounds = tester.getRect(choice);
        expect(bounds.width, greaterThanOrEqualTo(48));
        expect(bounds.height, greaterThanOrEqualTo(48));
        await tester.tap(choice);
      }
      expect(find.text('Original'), findsOneWidget);
      expect(find.text('Page words'), findsOneWidget);
      expect(find.text('Text'), findsOneWidget);
      expect(tapped, ['view pageWords', 'view text']);
      expect(tester.takeException(), isNull);
    });
  });
}
