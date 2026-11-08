import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs [check] each time [source] notifies, until the current test ends,
/// and fails the test when any of those checks threw.
///
/// A ChangeNotifier reports an error that its listener throws through
/// FlutterError and goes on, so a checkInvariants call in a plain listener
/// can never fail its test. This listener keeps each error instead. When
/// the test ends, it stops listening and expects no error, before the
/// tear-downs of the test's groups dispose [source].
void expectInvariantsAtEveryNotice(Listenable source, VoidCallback check) {
  final broken = <String>[];
  void checkNow() {
    try {
      check();
    } on Object catch (error, stack) {
      broken.add('$error\n$stack');
    }
  }

  source.addListener(checkNow);
  addTearDown(() {
    source.removeListener(checkNow);
    expect(broken, isEmpty, reason: 'An invariant failed at a notice.');
  });
}
