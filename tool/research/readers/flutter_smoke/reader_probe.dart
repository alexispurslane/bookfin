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
    const style = TextStyle(fontSize: 18, height: 1.4);
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout(maxWidth: width);
    final lines = painter.computeLineMetrics().length;
    painter.dispose();
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextButton(
            onPressed: onSource,
            child: Text('Source page $sourcePage, character $sourceCharacter'),
          ),
          Text('Width ${width.toInt()} logical pixels; $lines lines; body 18'),
          Text(text, style: style, textScaler: TextScaler.noScaling),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
