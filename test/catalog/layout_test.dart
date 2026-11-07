import 'package:bookfin/catalog/layout.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryLayoutStore implements LayoutStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async => this.value = value;
}

void main() {
  test('the library starts as a spacious grid', () async {
    final layout = LibraryLayout(MemoryLayoutStore());
    await layout.restore();
    expect(layout.view, LibraryView.grid);
    expect(layout.density, LibraryDensity.spacious);
  });

  test('a chosen view and density survive a restart', () async {
    final store = MemoryLayoutStore();
    final layout = LibraryLayout(store)
      ..view = LibraryView.list
      ..density = LibraryDensity.compact;
    await layout.saved;
    final restarted = LibraryLayout(store);
    await restarted.restore();
    expect(restarted.view, LibraryView.list);
    expect(restarted.density, LibraryDensity.compact);
  });

  test('an unreadable saved layout falls back to the default', () async {
    final layout = LibraryLayout(MemoryLayoutStore()..value = '{broken');
    await layout.restore();
    expect(layout.view, LibraryView.grid);
  });
}
