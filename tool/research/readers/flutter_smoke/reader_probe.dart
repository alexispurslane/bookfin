import 'package:flutter/material.dart';

class ReflowPage extends StatelessWidget {
  const ReflowPage({
    super.key,
    required this.text,
    required this.width,
    required this.sourcePage,
    required this.sourceCharacter,
    required this.onSource,
  });

  final String text;
  final double width;
  final int sourcePage;
  final int sourceCharacter;
  final VoidCallback onSource;

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style
        .merge(const TextStyle(fontSize: 18, height: 1.4));
    final span = TextSpan(text: text, style: style);
    final locale = Localizations.maybeLocaleOf(context);
    return SizedBox(
      width: width,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final actualWidth = constraints.maxWidth;
          final painter = TextPainter(
            text: span,
            textDirection: TextDirection.ltr,
            textScaler: TextScaler.noScaling,
            locale: locale,
          )..layout(maxWidth: actualWidth);
          final lines = painter.computeLineMetrics().length;
          painter.dispose();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextButton(
                onPressed: onSource,
                child: Text(
                  'Source page $sourcePage, character $sourceCharacter',
                ),
              ),
              Text(
                'Width ${actualWidth.toInt()} logical pixels; $lines lines; body 18',
              ),
              RichText(
                text: span,
                textDirection: TextDirection.ltr,
                textScaler: TextScaler.noScaling,
                locale: locale,
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}
