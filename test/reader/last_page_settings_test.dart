// The reader keeps the page settings of the last page that it showed on
// this phone, so that the next open of a book can prepare its first section
// before the reader's first layout gives the settings (boo-yjq6). They are
// derived data with a store of their own.
import 'package:bookfin/reader/epub/prepare.dart';
import 'package:bookfin/reader/last_page_settings.dart';
import 'package:flutter_test/flutter_test.dart';

/// A page settings store in memory.
class MemoryPageSettingsStore implements PageSettingsStore {
  MemoryPageSettingsStore([this.value]);
  String? value;
  var writes = 0;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async {
    writes++;
    this.value = value;
  }
}

const _phone = PageSettings(
  width: 392.7,
  height: 712.5,
  fontSize: 21.6,
  night: true,
  sizesMainText: true,
);

void main() {
  test('a new launch knows the settings of the last page that the reader '
      'showed', () async {
    final store = MemoryPageSettingsStore();
    LastPageSettings(store).keep(_phone);
    await pumpEventQueue();

    final relaunched = LastPageSettings(store);
    expect(relaunched.value, isNull);
    await relaunched.restore();

    expect(relaunched.value, _phone);
  });

  test('a page that shows before the kept value is read wins', () async {
    final store = MemoryPageSettingsStore();
    LastPageSettings(store).keep(_phone);
    await pumpEventQueue();

    final relaunched = LastPageSettings(store);
    final restoring = relaunched.restore();
    const other = PageSettings(
      width: 800,
      height: 600,
      fontSize: 18,
      night: false,
    );
    relaunched.keep(other);
    await restoring;

    expect(relaunched.value, other);
  });

  test('another page with the same settings writes nothing', () async {
    final store = MemoryPageSettingsStore();
    final last = LastPageSettings(store);

    last
      ..keep(_phone)
      ..keep(_phone)
      ..keep(_phone);
    await pumpEventQueue();

    expect(store.writes, 1);
  });

  for (final (name, value) in [
    ('that is not JSON', 'pages'),
    ('of another form', '{"version":1,"width":"wide"}'),
    (
      'without a page area',
      '{"version":1,"width":0,"height":712,"fontSize":20,"night":false,'
          '"sizesMainText":false}',
    ),
  ]) {
    test('a kept value $name gives no settings', () async {
      final last = LastPageSettings(MemoryPageSettingsStore(value));

      await last.restore();

      expect(last.value, isNull);
    });
  }
}
