import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:record_rows_bench/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('measures the reads of large personal-record accounts', (
    tester,
  ) async {
    await tester.runAsync(
      () => measure((line) {
        // ignore: avoid_print
        print('BENCH $line');
      }),
    );
  }, timeout: const Timeout(Duration(minutes: 20)));
}
