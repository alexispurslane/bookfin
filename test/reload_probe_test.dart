import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/reload_probe.dart';

void main() {
  testWidgets('the shared setup note survives widget reassembly', (
    tester,
  ) async {
    await tester.pumpWidget(const ReloadProbe());
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Shared Bookfin note');

    unawaited(tester.binding.reassembleApplication());
    await tester.pump();

    expect(find.text('Shared Bookfin note'), findsOneWidget);
  });
}
