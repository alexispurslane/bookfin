import 'package:bookfin/foundation/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> showChoice(
    WidgetTester tester, {
    required double width,
    double scale = 1,
    required ValueChanged<int> onChanged,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: bookfinTheme(Brightness.light),
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Center(
            child: SizedBox(
              width: width,
              child: PillChoice<int>(
                segments: const [
                  PillSegment(
                    value: 0,
                    label: 'Original',
                    icon: Icons.picture_as_pdf_outlined,
                  ),
                  PillSegment(
                    value: 1,
                    label: 'Page words',
                    icon: Icons.view_headline_rounded,
                  ),
                  PillSegment(
                    value: 2,
                    label: 'Text',
                    icon: Icons.article_outlined,
                  ),
                ],
                selected: 0,
                onChanged: onChanged,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('a wide choice keeps the icons beside full labels', (
    tester,
  ) async {
    await showChoice(tester, width: 780, onChanged: (_) {});
    expect(find.byIcon(Icons.picture_as_pdf_outlined), findsOneWidget);
    expect(find.byIcon(Icons.view_headline_rounded), findsOneWidget);
    expect(find.byIcon(Icons.article_outlined), findsOneWidget);
    expect(
      tester
          .widget<SegmentedButton<int>>(find.byType(SegmentedButton<int>))
          .direction,
      Axis.horizontal,
    );
  });

  testWidgets('a choice hides icons before it stacks its full labels', (
    tester,
  ) async {
    final chosen = <int>[];
    await showChoice(tester, width: 500, onChanged: chosen.add);
    expect(find.byIcon(Icons.picture_as_pdf_outlined), findsNothing);
    expect(find.byIcon(Icons.view_headline_rounded), findsNothing);
    expect(find.byIcon(Icons.article_outlined), findsNothing);
    expect(
      tester
          .widget<SegmentedButton<int>>(find.byType(SegmentedButton<int>))
          .direction,
      Axis.horizontal,
    );
    for (final label in ['Original', 'Page words', 'Text']) {
      final paragraph = tester.renderObject<RenderParagraph>(find.text(label));
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(
        paragraph.size.width,
        greaterThanOrEqualTo(paragraph.getMaxIntrinsicWidth(double.infinity)),
      );
    }
    await tester.tap(find.text('Page words'));
    await tester.tap(find.text('Text'));
    expect(chosen, [1, 2]);
  });

  testWidgets('large-text choices stack whole labels with full touch targets', (
    tester,
  ) async {
    final chosen = <int>[];
    await showChoice(tester, width: 280, scale: 3.2, onChanged: chosen.add);
    expect(
      tester
          .widget<SegmentedButton<int>>(find.byType(SegmentedButton<int>))
          .direction,
      Axis.vertical,
    );
    expect(find.byIcon(Icons.view_headline_rounded), findsNothing);
    final segmented = find.byType(SegmentedButton<int>);
    final context = tester.element(segmented);
    final shape =
        tester
            .widget<SegmentedButton<int>>(segmented)
            .style
            ?.shape
            ?.resolve({}) ??
        SegmentedButtonTheme.of(context).style!.shape!.resolve({})!;
    final clip = shape.getInnerPath(
      tester.getRect(segmented),
      textDirection: Directionality.of(context),
    );
    var previousBottom = 0.0;
    for (final label in ['Original', 'Page words', 'Text']) {
      final button = find.ancestor(
        of: find.text(label),
        matching: find.byType(TextButton),
      );
      final bounds = tester.getRect(button);
      expect(bounds.width, greaterThanOrEqualTo(48));
      expect(bounds.height, greaterThanOrEqualTo(48));
      expect(bounds.left, greaterThanOrEqualTo(tester.getRect(segmented).left));
      expect(bounds.right, lessThanOrEqualTo(tester.getRect(segmented).right));
      expect(bounds.top, greaterThanOrEqualTo(previousBottom));
      previousBottom = bounds.bottom;
      final paragraph = tester.renderObject<RenderParagraph>(find.text(label));
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(paragraph.text.toPlainText(), label);
      final lines = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: label.length),
      );
      for (final line in lines) {
        expect(line.left, greaterThanOrEqualTo(0));
        expect(line.right, lessThanOrEqualTo(paragraph.size.width));
        expect(line.bottom, lessThanOrEqualTo(paragraph.size.height));
        final visible = line
            .toRect()
            .shift(paragraph.localToGlobal(Offset.zero))
            .deflate(1);
        expect(
          clip.contains(visible.topLeft),
          isTrue,
          reason: '$label must not be clipped by the rounded upper end.',
        );
        expect(
          clip.contains(visible.bottomRight),
          isTrue,
          reason: '$label must not be clipped by the rounded lower end.',
        );
      }
      await tester.tap(button);
    }
    expect(chosen, [1, 2]);
    expect(tester.takeException(), isNull);
  });
}
