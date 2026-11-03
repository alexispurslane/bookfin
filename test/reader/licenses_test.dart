import 'package:bookfin/reader/licenses.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('reader notices expose the bundled native licenses including non-UTF8 notices', () async {
    final entries = await readerLicenses().toList();
    expect(
      entries.any(
        (entry) => entry.packages.any((name) => name.contains('libmobi')),
      ),
      isTrue,
    );
    final text = entries
        .expand((entry) => entry.paragraphs)
        .map((paragraph) => paragraph.text)
        .join('\n');
    expect(text, contains('GNU LESSER GENERAL PUBLIC LICENSE'));
    expect(text, contains('GNU GENERAL PUBLIC LICENSE'));
    expect(text, contains('FreeType'));
    expect(text, contains('libmobi 0.12'));
    expect(text, isNot(contains('\uFFFD')));
  });
}
