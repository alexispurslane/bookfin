import 'package:bookfin/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Bookfin identifies itself before a library is connected', (
    tester,
  ) async {
    await tester.pumpWidget(const BookfinApp());

    expect(find.text('Bookfin'), findsOneWidget);
    expect(find.text('Your library starts here.'), findsOneWidget);
  });

  testWidgets('the setup shell does not pretend that books are available', (
    tester,
  ) async {
    await tester.pumpWidget(const BookfinApp());

    expect(
      find.text('Library connection is not available in this setup build.'),
      findsOneWidget,
    );
    expect(find.byType(FloatingActionButton), findsNothing);
  });
}
