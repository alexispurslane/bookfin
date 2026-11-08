import 'package:flutter_test/flutter_test.dart';

/// Opens the reader's Reading settings sheet, taps the control named
/// [tooltip] in it, and closes the sheet with a tap outside it. After each
/// step it lets the sheet's slide finish, then waits with [settle], by
/// default until no frame is scheduled.
Future<void> chooseSetting(
  WidgetTester tester,
  String tooltip, {
  Future<void> Function()? settle,
}) async {
  Future<void> wait() async {
    // The slide starts on the first frame and then takes its time.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await (settle?.call() ?? tester.pumpAndSettle());
  }

  await tester.tap(find.byTooltip('Reading settings'));
  await wait();
  await tester.tap(find.byTooltip(tooltip));
  await wait();
  await tester.tapAt(const Offset(20, 20));
  await wait();
}
